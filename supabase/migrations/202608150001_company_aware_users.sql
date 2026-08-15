create table public.fuel_companies (
  id uuid primary key default gen_random_uuid(),
  company_code text not null unique,
  company_name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint fuel_companies_code_not_blank
    check (btrim(company_code) <> ''),

  constraint fuel_companies_name_not_blank
    check (btrim(company_name) <> '')
);

insert into public.fuel_companies (
  company_code,
  company_name
)
values
  ('PETRONAS', 'Petronas'),
  ('SHELL', 'Shell'),
  ('PETRON', 'Petron'),
  ('CALTEX', 'Caltex'),
  ('BHPETROL', 'BHPetrol')
on conflict do nothing;

alter table public.profiles
add column if not exists company_id uuid null;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'profiles_company_id_fkey'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_company_id_fkey
      foreign key (company_id)
      references public.fuel_companies(id);
  end if;
end;
$$;

create index if not exists profiles_company_id_idx
on public.profiles (company_id);

-- Normalize the original role, and conservatively map any unexpected legacy
-- role to the least-privileged supported role before enforcing the constraint.
update public.profiles
set role = 'company_user'
where role not in ('company_user', 'company_admin');

alter table public.profiles
alter column role set default 'company_user';

alter table public.profiles
drop constraint if exists profiles_role_supported_check;

alter table public.profiles
add constraint profiles_role_supported_check
check (role in ('company_user', 'company_admin'));

comment on column public.profiles.company_id is
  'Fuel-company membership. Nullable until the later company-claiming rollout.';

comment on column public.profiles.role is
  'Company authorization role; assignment is not writable by authenticated clients.';

alter table public.fuel_companies enable row level security;

drop policy if exists "Authenticated users can view active fuel companies"
on public.fuel_companies;

create policy "Authenticated users can view active fuel companies"
on public.fuel_companies
for select
to authenticated
using (is_active = true);

-- RLS has no write policies for this table. Explicit privilege revocation also
-- prevents ordinary API roles from writing if policies are broadened by mistake.
revoke all privileges on table public.fuel_companies from anon;
revoke insert, update, delete, truncate, references, trigger
on table public.fuel_companies from authenticated;
grant select on table public.fuel_companies to authenticated;

-- The existing owner-update RLS policy still limits rows by auth.uid(). These
-- column grants additionally limit which profile fields an authenticated client
-- can change. Company and role assignment must use a later privileged workflow.
revoke update on table public.profiles from authenticated;
revoke update (
  id,
  user_id,
  full_name,
  email,
  phone,
  role,
  created_at,
  updated_at,
  company_id
)
on public.profiles from authenticated;

grant update (
  full_name,
  phone,
  updated_at
)
on public.profiles to authenticated;

-- Module 1 defines this shared trigger function before this migration runs.
do $$
begin
  if pg_catalog.to_regprocedure('public.update_updated_at_column()') is null then
    raise exception
      'Required function public.update_updated_at_column() is missing';
  end if;
end;
$$;

drop trigger if exists update_fuel_companies_updated_at
on public.fuel_companies;

create trigger update_fuel_companies_updated_at
before update on public.fuel_companies
for each row
execute function public.update_updated_at_column();

drop trigger if exists update_profiles_updated_at
on public.profiles;

create trigger update_profiles_updated_at
before update on public.profiles
for each row
execute function public.update_updated_at_column();
