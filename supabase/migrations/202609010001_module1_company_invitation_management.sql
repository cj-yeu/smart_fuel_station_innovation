-- Module 1 company-admin invitation management. Raw invitation codes are
-- generated inside the database, returned only once, and never persisted.

do $module1_invitation_management_preconditions$
begin
  if pg_catalog.to_regclass('public.company_invitation_codes') is null
    or pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.fuel_companies') is null
    or pg_catalog.to_regclass('auth.users') is null then
    raise exception 'Module 1 company invitation prerequisites are missing';
  end if;

  if pg_catalog.to_regprocedure('public.claim_company_membership(text,text)') is null
    or pg_catalog.to_regprocedure('public.update_updated_at_column()') is null then
    raise exception 'Required Module 1 invitation functions are missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_roles where rolname = 'authenticated'
  ) or not exists (
    select 1 from pg_catalog.pg_roles where rolname = 'anon'
  ) or not exists (
    select 1 from pg_catalog.pg_roles where rolname = 'service_role'
  ) then
    raise exception 'Required Supabase API roles are missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_extension as extension_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = extension_entry.extnamespace
    where extension_entry.extname = 'pgcrypto'
      and namespace_entry.nspname = 'extensions'
  ) then
    raise exception 'pgcrypto must be installed in the extensions schema';
  end if;

  -- These RPC names are new to this migration. An existing non-exact routine
  -- could retain a different ACL, so fail closed rather than replacing or
  -- silently coexisting with an unexpected overload.
  if exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and (
        (
          function_entry.proname = 'create_company_invitation_code'
          and (
            function_entry.prokind <> 'f'
            or function_entry.oid is distinct from pg_catalog.to_regprocedure(
              'public.create_company_invitation_code(integer,integer)'
            )
          )
        )
        or (
          function_entry.proname = 'list_company_invitation_codes'
          and (
            function_entry.prokind <> 'f'
            or function_entry.oid is distinct from pg_catalog.to_regprocedure(
              'public.list_company_invitation_codes()'
            )
          )
        )
        or (
          function_entry.proname = 'revoke_company_invitation_code'
          and (
            function_entry.prokind <> 'f'
            or function_entry.oid is distinct from pg_catalog.to_regprocedure(
              'public.revoke_company_invitation_code(uuid)'
            )
          )
        )
      )
  ) then
    raise exception 'Unexpected Module 1 invitation management RPC overload exists';
  end if;
end;
$module1_invitation_management_preconditions$;

alter table public.company_invitation_codes
  add column created_by_user_id uuid null
    references auth.users(id) on delete set null,
  add column code_hint text null,
  add column revoked_at timestamptz null,
  add column revoked_by_user_id uuid null
    references auth.users(id) on delete set null;

alter table public.company_invitation_codes
  add constraint company_invitation_codes_code_hint_valid
  check (
    code_hint is null
    or (pg_catalog.btrim(code_hint) <> '' and pg_catalog.char_length(code_hint) <= 32)
  );

create index company_invitation_codes_management_status_idx
on public.company_invitation_codes (
  company_id,
  is_active,
  revoked_at,
  expires_at,
  created_at desc
);

create or replace function public.create_company_invitation_code(
  p_expiry_days integer,
  p_max_uses integer
)
returns table (
  invitation_id uuid,
  invitation_code text,
  expires_at timestamptz,
  max_uses integer
)
language plpgsql
security definer
set search_path = ''
as $module1_create_invitation$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_active_code_count integer;
  v_raw_code text;
  v_code_hash text;
  v_code_hint text;
  v_expires_at timestamptz;
  v_invitation_id uuid;
  v_attempt integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if p_expiry_days is null or p_expiry_days < 1 or p_expiry_days > 30 then
    raise exception 'Expiry must be between 1 and 30 days' using errcode = '22023';
  end if;

  if p_max_uses is null or p_max_uses < 1 or p_max_uses > 20 then
    raise exception 'Maximum uses must be between 1 and 20' using errcode = '22023';
  end if;

  select profile.company_id
  into v_company_id
  from public.profiles as profile
  join public.fuel_companies as company
    on company.id = profile.company_id
  where profile.user_id = v_user_id
    and profile.role = 'company_admin'
    and company.is_active
  for update of company;

  if v_company_id is null then
    raise exception 'Company administrator access is required' using errcode = '28000';
  end if;

  select pg_catalog.count(*)
  into v_active_code_count
  from public.company_invitation_codes as invitation
  where invitation.company_id = v_company_id
    and invitation.is_active
    and invitation.revoked_at is null
    and (invitation.expires_at is null or invitation.expires_at > pg_catalog.now())
    and (invitation.max_uses is null or invitation.use_count < invitation.max_uses);

  if v_active_code_count >= 20 then
    raise exception 'The company already has the maximum number of active invitation codes'
      using errcode = '22023';
  end if;

  v_expires_at := pg_catalog.now() + p_expiry_days * interval '1 day';

  -- 12 random bytes provide 96 bits of entropy. The four six-character
  -- uppercase groups are hashed with the exact btrim/UTF-8/SHA-256 scheme
  -- used by claim_company_membership.
  for v_attempt in 1..8 loop
    v_raw_code := pg_catalog.upper(
      pg_catalog.encode(extensions.gen_random_bytes(12), 'hex')
    );
    v_raw_code := pg_catalog.substring(v_raw_code from 1 for 6)
      || '-' || pg_catalog.substring(v_raw_code from 7 for 6)
      || '-' || pg_catalog.substring(v_raw_code from 13 for 6)
      || '-' || pg_catalog.substring(v_raw_code from 19 for 6);
    v_code_hash := pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(pg_catalog.btrim(v_raw_code), 'UTF8'),
        'sha256'
      ),
      'hex'
    );
    v_code_hint := '••••-' || pg_catalog.right(v_raw_code, 4);

    begin
      insert into public.company_invitation_codes (
        company_id,
        code_hash,
        assigned_role,
        is_active,
        expires_at,
        max_uses,
        use_count,
        created_by_user_id,
        code_hint
      )
      values (
        v_company_id,
        v_code_hash,
        'company_user',
        true,
        v_expires_at,
        p_max_uses,
        0,
        v_user_id,
        v_code_hint
      )
      returning id into v_invitation_id;
      exit;
    exception
      when unique_violation then
        -- A SHA-256 collision from 96 random bits is extraordinarily unlikely;
        -- retry without exposing or storing the attempted raw code.
        v_invitation_id := null;
    end;
  end loop;

  if v_invitation_id is null then
    raise exception 'A secure invitation code could not be generated'
      using errcode = 'P0001';
  end if;

  return query select v_invitation_id, v_raw_code, v_expires_at, p_max_uses;
end;
$module1_create_invitation$;

create or replace function public.list_company_invitation_codes()
returns table (
  invitation_id uuid,
  code_hint text,
  created_at timestamptz,
  expires_at timestamptz,
  max_uses integer,
  used_count integer,
  assigned_role text,
  revoked_at timestamptz,
  status text
)
language plpgsql
security definer
set search_path = ''
as $module1_list_invitations$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  select profile.company_id
  into v_company_id
  from public.profiles as profile
  join public.fuel_companies as company
    on company.id = profile.company_id
  where profile.user_id = v_user_id
    and profile.role = 'company_admin'
    and company.is_active
  for share of profile, company;

  if v_company_id is null then
    raise exception 'Company administrator access is required' using errcode = '28000';
  end if;

  return query
  select
    invitation.id,
    pg_catalog.coalesce(invitation.code_hint, 'Legacy invitation'),
    invitation.created_at,
    invitation.expires_at,
    invitation.max_uses,
    invitation.use_count,
    invitation.assigned_role,
    invitation.revoked_at,
    case
      when invitation.revoked_at is not null or not invitation.is_active then 'revoked'
      when invitation.expires_at is not null and invitation.expires_at <= pg_catalog.now() then 'expired'
      when invitation.max_uses is not null and invitation.use_count >= invitation.max_uses then 'used_up'
      else 'active'
    end
  from public.company_invitation_codes as invitation
  where invitation.company_id = v_company_id
  order by invitation.created_at desc, invitation.id;
end;
$module1_list_invitations$;

create or replace function public.revoke_company_invitation_code(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $module1_revoke_invitation$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;

  if p_invitation_id is null then
    raise exception 'Invitation identifier is required' using errcode = '22023';
  end if;

  select profile.company_id
  into v_company_id
  from public.profiles as profile
  join public.fuel_companies as company
    on company.id = profile.company_id
  where profile.user_id = v_user_id
    and profile.role = 'company_admin'
    and company.is_active
  for share of profile, company;

  if v_company_id is null then
    raise exception 'Company administrator access is required' using errcode = '28000';
  end if;

  update public.company_invitation_codes as invitation
  set
    is_active = false,
    revoked_at = pg_catalog.coalesce(invitation.revoked_at, pg_catalog.now()),
    revoked_by_user_id = pg_catalog.coalesce(invitation.revoked_by_user_id, v_user_id),
    updated_at = pg_catalog.now()
  where invitation.id = p_invitation_id
    and invitation.company_id = v_company_id;

  if not found then
    raise exception 'Invitation code was not found' using errcode = 'P0002';
  end if;

  return true;
end;
$module1_revoke_invitation$;

-- Preserve the existing atomic claim flow. The only semantic addition is that
-- an explicitly revoked code cannot be used even if a legacy row still has an
-- active flag set unexpectedly.
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
as $module1_claim_company_membership$
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
  v_revoked_at timestamptz;
  v_updated_rows integer;
begin
  if v_user_id is null then
    raise exception 'Authentication is required' using errcode = '28000';
  end if;
  if p_company_code is null or pg_catalog.btrim(p_company_code) = '' then
    raise exception 'Company code is required' using errcode = '22023';
  end if;
  if p_invitation_code is null or pg_catalog.btrim(p_invitation_code) = '' then
    raise exception 'Invitation code is required' using errcode = '22023';
  end if;

  select company.id, company.company_code, company.company_name
  into v_company_id, v_company_code, v_company_name
  from public.fuel_companies as company
  where company.is_active
    and pg_catalog.lower(pg_catalog.btrim(company.company_code)) =
      pg_catalog.lower(pg_catalog.btrim(p_company_code))
  for share;

  if not found then
    raise exception 'Active fuel company not found' using errcode = 'P0002';
  end if;

  v_code_hash := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(pg_catalog.btrim(p_invitation_code), 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select
    invitation.id,
    invitation.assigned_role,
    invitation.is_active,
    invitation.expires_at,
    invitation.max_uses,
    invitation.use_count,
    invitation.revoked_at
  into
    v_invitation_id,
    v_assigned_role,
    v_is_active,
    v_expires_at,
    v_max_uses,
    v_use_count,
    v_revoked_at
  from public.company_invitation_codes as invitation
  where invitation.company_id = v_company_id
    and invitation.code_hash = v_code_hash
  for update;

  if not found then
    raise exception 'Invitation code is invalid' using errcode = '22023';
  end if;
  if not v_is_active or v_revoked_at is not null then
    raise exception 'Invitation code is inactive' using errcode = '22023';
  end if;
  if v_expires_at is not null and v_expires_at <= pg_catalog.now() then
    raise exception 'Invitation code has expired' using errcode = '22023';
  end if;
  if v_max_uses is not null and v_use_count >= v_max_uses then
    raise exception 'Invitation code has reached its usage limit' using errcode = '22023';
  end if;

  select profile.id, profile.company_id
  into v_profile_id, v_existing_company_id
  from public.profiles as profile
  where profile.user_id = v_user_id
  for update;
  if not found then
    raise exception 'A profile is required before claiming membership' using errcode = 'P0002';
  end if;
  if v_existing_company_id is not null then
    raise exception 'The current profile already has a company membership' using errcode = '23505';
  end if;

  update public.profiles as profile
  set company_id = v_company_id, role = v_assigned_role, updated_at = pg_catalog.now()
  where profile.id = v_profile_id
    and profile.user_id = v_user_id
    and profile.company_id is null;
  get diagnostics v_updated_rows = row_count;
  if v_updated_rows <> 1 then
    raise exception 'Company membership could not be assigned' using errcode = '40001';
  end if;

  update public.company_invitation_codes as invitation
  set use_count = invitation.use_count + 1, updated_at = pg_catalog.now()
  where invitation.id = v_invitation_id;

  return query select v_profile_id, v_user_id, v_company_id, v_company_code,
    v_company_name, v_assigned_role;
end;
$module1_claim_company_membership$;

-- Check routine cardinality and exact typed identities before granting API
-- execution. This prevents an unreviewed overload from retaining an ACL.
do $module1_invitation_management_rpc_signature_postconditions$
begin
  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'create_company_invitation_code'
  ) <> 1
    or not exists (
      select 1
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_namespace as namespace_entry
        on namespace_entry.oid = function_entry.pronamespace
      where namespace_entry.nspname = 'public'
        and function_entry.proname = 'create_company_invitation_code'
        and function_entry.prokind = 'f'
        and function_entry.oid = pg_catalog.to_regprocedure(
          'public.create_company_invitation_code(integer,integer)'
        )
        and function_entry.pronargs = 2
        and function_entry.proargtypes[0] =
          'pg_catalog.int4'::pg_catalog.regtype
        and function_entry.proargtypes[1] =
          'pg_catalog.int4'::pg_catalog.regtype
    )
    or (
      select pg_catalog.count(*)
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_namespace as namespace_entry
        on namespace_entry.oid = function_entry.pronamespace
      where namespace_entry.nspname = 'public'
        and function_entry.proname = 'list_company_invitation_codes'
    ) <> 1
    or not exists (
      select 1
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_namespace as namespace_entry
        on namespace_entry.oid = function_entry.pronamespace
      where namespace_entry.nspname = 'public'
        and function_entry.proname = 'list_company_invitation_codes'
        and function_entry.prokind = 'f'
        and function_entry.oid = pg_catalog.to_regprocedure(
          'public.list_company_invitation_codes()'
        )
        and function_entry.pronargs = 0
        and function_entry.proargtypes = ''::pg_catalog.oidvector
    )
    or (
      select pg_catalog.count(*)
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_namespace as namespace_entry
        on namespace_entry.oid = function_entry.pronamespace
      where namespace_entry.nspname = 'public'
        and function_entry.proname = 'revoke_company_invitation_code'
    ) <> 1
    or not exists (
      select 1
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_namespace as namespace_entry
        on namespace_entry.oid = function_entry.pronamespace
      where namespace_entry.nspname = 'public'
        and function_entry.proname = 'revoke_company_invitation_code'
        and function_entry.prokind = 'f'
        and function_entry.oid = pg_catalog.to_regprocedure(
          'public.revoke_company_invitation_code(uuid)'
        )
        and function_entry.pronargs = 1
        and function_entry.proargtypes[0] =
          'pg_catalog.uuid'::pg_catalog.regtype
    ) then
    raise exception 'Module 1 invitation management RPC signatures are invalid';
  end if;
end;
$module1_invitation_management_rpc_signature_postconditions$;

revoke all privileges on table public.company_invitation_codes from public;
revoke all privileges on table public.company_invitation_codes from anon;
revoke all privileges on table public.company_invitation_codes from authenticated;

revoke all privileges on function public.create_company_invitation_code(integer, integer) from public;
revoke all privileges on function public.create_company_invitation_code(integer, integer) from anon;
revoke all privileges on function public.create_company_invitation_code(integer, integer) from authenticated;
grant execute on function public.create_company_invitation_code(integer, integer) to authenticated;

revoke all privileges on function public.list_company_invitation_codes() from public;
revoke all privileges on function public.list_company_invitation_codes() from anon;
revoke all privileges on function public.list_company_invitation_codes() from authenticated;
grant execute on function public.list_company_invitation_codes() to authenticated;

revoke all privileges on function public.revoke_company_invitation_code(uuid) from public;
revoke all privileges on function public.revoke_company_invitation_code(uuid) from anon;
revoke all privileges on function public.revoke_company_invitation_code(uuid) from authenticated;
grant execute on function public.revoke_company_invitation_code(uuid) to authenticated;

do $module1_invitation_management_postconditions$
declare
  v_function regprocedure;
begin
  foreach v_function in array[
    'public.create_company_invitation_code(integer,integer)'::regprocedure,
    'public.list_company_invitation_codes()'::regprocedure,
    'public.revoke_company_invitation_code(uuid)'::regprocedure
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_proc as function_entry
      join pg_catalog.pg_roles as owner_entry on owner_entry.oid = function_entry.proowner
      where function_entry.oid = v_function
        and function_entry.prosecdef
        and owner_entry.rolname not in ('anon', 'authenticated', 'service_role')
        and function_entry.proconfig = array['search_path=""']::text[]
    ) then
      raise exception 'Invitation management RPC security configuration is invalid';
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    cross join lateral pg_catalog.aclexplode(
      pg_catalog.coalesce(
        procedure_entry.proacl,
        pg_catalog.acldefault('f', procedure_entry.proowner)
      )
    ) as function_acl
    where procedure_entry.oid = any(
      array[
        'public.create_company_invitation_code(integer,integer)'::regprocedure,
        'public.list_company_invitation_codes()'::regprocedure,
        'public.revoke_company_invitation_code(uuid)'::regprocedure
      ]
    )
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  )
    or pg_catalog.has_function_privilege('anon', 'public.create_company_invitation_code(integer,integer)', 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', 'public.create_company_invitation_code(integer,integer)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.create_company_invitation_code(integer,integer)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.list_company_invitation_codes()', 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', 'public.list_company_invitation_codes()', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.list_company_invitation_codes()', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.revoke_company_invitation_code(uuid)', 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', 'public.revoke_company_invitation_code(uuid)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.revoke_company_invitation_code(uuid)', 'EXECUTE') then
    raise exception 'Invitation management RPC execute grants are invalid';
  end if;
end;
$module1_invitation_management_postconditions$;
