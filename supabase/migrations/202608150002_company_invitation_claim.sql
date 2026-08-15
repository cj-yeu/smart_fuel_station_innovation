create schema if not exists extensions;

create extension if not exists pgcrypto
with schema extensions;

-- Supabase conventionally installs pgcrypto in the extensions schema. Fail
-- clearly instead of relying on a mutable search_path if it is installed elsewhere.
do $$
declare
  v_extension_schema text;
begin
  select namespace.nspname
  into v_extension_schema
  from pg_catalog.pg_extension as ext
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = ext.extnamespace
  where ext.extname = 'pgcrypto';

  if v_extension_schema is distinct from 'extensions' then
    raise exception
      'pgcrypto must be installed in the extensions schema';
  end if;
end;
$$;

create table public.company_invitation_codes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null
    references public.fuel_companies(id) on delete cascade,
  code_hash text not null unique,
  assigned_role text not null default 'company_user',
  is_active boolean not null default true,
  expires_at timestamptz null,
  max_uses integer null,
  use_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint company_invitation_codes_hash_not_blank
    check (btrim(code_hash) <> ''),

  constraint company_invitation_codes_hash_format
    check (code_hash ~ '^[0-9a-f]{64}$'),

  constraint company_invitation_codes_role_supported
    check (assigned_role in ('company_user', 'company_admin')),

  constraint company_invitation_codes_max_uses_positive
    check (max_uses is null or max_uses > 0),

  constraint company_invitation_codes_use_count_nonnegative
    check (use_count >= 0),

  constraint company_invitation_codes_use_count_within_limit
    check (max_uses is null or use_count <= max_uses)
);

create index company_invitation_codes_company_id_idx
on public.company_invitation_codes (company_id);

create index company_invitation_codes_active_lookup_idx
on public.company_invitation_codes (company_id, code_hash)
where is_active = true;

-- This guarantees that the case-insensitive company lookup used by the claim
-- function resolves to at most one company.
create unique index if not exists fuel_companies_code_normalized_unique_idx
on public.fuel_companies (
  pg_catalog.lower(pg_catalog.btrim(company_code))
);

alter table public.company_invitation_codes enable row level security;

-- No RLS policies are created: invitation rows are deliberately invisible and
-- unwritable through the anon and authenticated API roles.
revoke all privileges
on table public.company_invitation_codes from public;

revoke all privileges
on table public.company_invitation_codes from anon;

revoke all privileges
on table public.company_invitation_codes from authenticated;

do $$
begin
  if pg_catalog.to_regprocedure('public.update_updated_at_column()') is null then
    raise exception
      'Required function public.update_updated_at_column() is missing';
  end if;
end;
$$;

drop trigger if exists update_company_invitation_codes_updated_at
on public.company_invitation_codes;

create trigger update_company_invitation_codes_updated_at
before update on public.company_invitation_codes
for each row
execute function public.update_updated_at_column();

create or replace function public.claim_company_membership(
  p_company_code text,
  p_invitation_code text
)
returns table (
  claimed_profile_id uuid,
  claimed_user_id uuid,
  claimed_company_id uuid,
  claimed_company_code text,
  claimed_company_name text,
  membership_role text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_existing_company_id uuid;
  v_company_id uuid;
  v_company_code text;
  v_company_name text;
  v_code_hash text;
  v_invitation_id uuid;
  v_assigned_role text;
  v_is_active boolean;
  v_expires_at timestamptz;
  v_max_uses integer;
  v_use_count integer;
  v_updated_rows integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required'
      using errcode = '28000';
  end if;

  if p_company_code is null
    or pg_catalog.btrim(p_company_code) = '' then
    raise exception 'Company code is required'
      using errcode = '22023';
  end if;

  if p_invitation_code is null
    or pg_catalog.btrim(p_invitation_code) = '' then
    raise exception 'Invitation code is required'
      using errcode = '22023';
  end if;

  select
    company.id,
    company.company_code,
    company.company_name
  into
    v_company_id,
    v_company_code,
    v_company_name
  from public.fuel_companies as company
  where company.is_active = true
    and pg_catalog.lower(pg_catalog.btrim(company.company_code)) =
      pg_catalog.lower(pg_catalog.btrim(p_company_code))
  for share;

  if not found then
    raise exception 'Active fuel company not found'
      using errcode = 'P0002';
  end if;

  -- The raw code remains only in the function argument and is trimmed before
  -- hashing. High entropy makes deterministic SHA-256 lookup resistant to
  -- practical guessing attacks.
  v_code_hash := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.btrim(p_invitation_code),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  -- Lock before checking status and usage. Concurrent claims for the same code
  -- serialize here, so a finite-use invitation cannot be over-consumed.
  select
    invitation.id,
    invitation.assigned_role,
    invitation.is_active,
    invitation.expires_at,
    invitation.max_uses,
    invitation.use_count
  into
    v_invitation_id,
    v_assigned_role,
    v_is_active,
    v_expires_at,
    v_max_uses,
    v_use_count
  from public.company_invitation_codes as invitation
  where invitation.company_id = v_company_id
    and invitation.code_hash = v_code_hash
  for update;

  if not found then
    raise exception 'Invitation code is invalid'
      using errcode = '22023';
  end if;

  if not v_is_active then
    raise exception 'Invitation code is inactive'
      using errcode = '22023';
  end if;

  if v_expires_at is not null
    and v_expires_at <= pg_catalog.now() then
    raise exception 'Invitation code has expired'
      using errcode = '22023';
  end if;

  if v_max_uses is not null
    and v_use_count >= v_max_uses then
    raise exception 'Invitation code has reached its usage limit'
      using errcode = '22023';
  end if;

  -- Lock the caller's own profile so simultaneous claims by the same account
  -- cannot assign two memberships or consume two invitations.
  select
    profile.id,
    profile.company_id
  into
    v_profile_id,
    v_existing_company_id
  from public.profiles as profile
  where profile.user_id = v_user_id
  for update;

  if not found then
    raise exception 'A profile is required before claiming membership'
      using errcode = 'P0002';
  end if;

  if v_existing_company_id is not null then
    raise exception 'The current profile already has a company membership'
      using errcode = '23505';
  end if;

  -- SECURITY DEFINER lets the function owner update protected columns. Direct
  -- authenticated profile updates remain limited by the existing column grants.
  update public.profiles as profile
  set
    company_id = v_company_id,
    role = v_assigned_role,
    updated_at = pg_catalog.now()
  where profile.id = v_profile_id
    and profile.user_id = v_user_id
    and profile.company_id is null;

  get diagnostics v_updated_rows = row_count;

  if v_updated_rows <> 1 then
    raise exception 'Company membership could not be assigned'
      using errcode = '40001';
  end if;

  update public.company_invitation_codes as invitation
  set
    use_count = invitation.use_count + 1,
    updated_at = pg_catalog.now()
  where invitation.id = v_invitation_id;

  return query
  select
    v_profile_id,
    v_user_id,
    v_company_id,
    v_company_code,
    v_company_name,
    v_assigned_role;
end;
$$;

-- Functions are executable by PUBLIC by default, so remove all implicit access
-- before granting the RPC only to authenticated application users.
revoke all privileges
on function public.claim_company_membership(text, text) from public;

revoke all privileges
on function public.claim_company_membership(text, text) from anon;

revoke all privileges
on function public.claim_company_membership(text, text) from authenticated;

grant execute
on function public.claim_company_membership(text, text) to authenticated;

comment on table public.company_invitation_codes is
  'Stores only cryptographic hashes of high-entropy invitation codes; raw codes are never stored.';

comment on function public.claim_company_membership(text, text) is
  'Validates a user-entered invitation code and atomically assigns the authenticated user to its company.';

-- Raw invitation codes must never be stored in this table or in source control.
-- Generate high-entropy codes outside this migration. A trusted database
-- administrator inserts only the lowercase SHA-256 hash. The application passes
-- the user-entered raw code only to claim_company_membership for in-database hashing.
