alter table public.fuel_companies enable row level security;

drop policy if exists "Anonymous users can view active fuel companies"
on public.fuel_companies;

create policy "Anonymous users can view active fuel companies"
on public.fuel_companies
for select
to anon
using (is_active = true);

-- Start from no table privileges, then grant only the read access required by
-- the registration company picker. RLS still limits anon to active companies.
revoke all privileges
on table public.fuel_companies from anon;

grant select
on table public.fuel_companies to anon;

comment on policy "Anonymous users can view active fuel companies"
on public.fuel_companies is
  'Public company discovery is only for the registration UI and does not establish company membership or authorization.';
