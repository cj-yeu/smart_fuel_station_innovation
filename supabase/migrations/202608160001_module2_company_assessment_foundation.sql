-- Module 2 company-assessment ownership and RLS foundation.
--
-- public.profiles.company_id is the authoritative company-membership source.
-- Assessment ownership is derived and validated in PostgreSQL; auth metadata and
-- client-supplied ownership values are never authoritative.

alter table public.station_assessments
add column company_id uuid null;

alter table public.station_assessments
add constraint station_assessments_company_id_fkey
foreign key (company_id)
references public.fuel_companies(id);

comment on column public.station_assessments.company_id is
  'Authoritative assessment company ownership, derived from profiles.company_id. Nullable only so unresolved legacy rows can be preserved during rollout.';

-- Preserve legacy timestamps while assigning every ownership value that can be
-- resolved through station_assessments.user_id -> profiles.user_id ->
-- profiles.company_id. Rows without a resolvable membership remain untouched.
alter table public.station_assessments
disable trigger update_station_assessments_updated_at;

update public.station_assessments as assessment
set company_id = profile.company_id
from public.profiles as profile
where profile.user_id = assessment.user_id
  and profile.company_id is not null
  and assessment.company_id is null;

alter table public.station_assessments
enable trigger update_station_assessments_updated_at;

create index station_assessments_user_id_idx
on public.station_assessments (user_id);

create index station_assessments_company_id_idx
on public.station_assessments (company_id);

create index station_assessments_company_created_at_idx
on public.station_assessments (company_id, created_at desc);

-- These SECURITY DEFINER helpers read only the caller's authoritative profile.
-- Keeping profile lookup outside assessment policies avoids profiles-RLS
-- recursion and lets company collaboration work without exposing other profiles.
create function public.current_assessment_company_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select profile.company_id
  from public.profiles as profile
  where profile.user_id = auth.uid()
$$;

create function public.current_user_is_company_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select profile.company_id is not null
        and profile.role = 'company_admin'
      from public.profiles as profile
      where profile.user_id = auth.uid()
    ),
    false
  )
$$;

revoke all privileges
on function public.current_assessment_company_id() from public;

revoke all privileges
on function public.current_assessment_company_id() from anon;

revoke all privileges
on function public.current_assessment_company_id() from authenticated;

grant execute
on function public.current_assessment_company_id() to authenticated;

revoke all privileges
on function public.current_user_is_company_admin() from public;

revoke all privileges
on function public.current_user_is_company_admin() from anon;

revoke all privileges
on function public.current_user_is_company_admin() from authenticated;

grant execute
on function public.current_user_is_company_admin() to authenticated;

comment on function public.current_assessment_company_id() is
  'Returns profiles.company_id for auth.uid(); used by Module 2 RLS without trusting auth metadata.';

comment on function public.current_user_is_company_admin() is
  'Returns whether auth.uid() has an authoritative company_admin profile with non-null company membership.';

-- New rows must belong to the authenticated caller and the company recorded on
-- that caller's profile. Correct client-supplied values are accepted for backward
-- compatibility, but missing values are filled and conflicting values fail.
create function public.set_station_assessment_ownership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication is required to create an assessment'
      using errcode = '42501';
  end if;

  select profile.company_id
  into v_company_id
  from public.profiles as profile
  where profile.user_id = v_user_id;

  if not found or v_company_id is null then
    raise exception 'An authoritative company membership is required to create an assessment'
      using errcode = '42501';
  end if;

  if new.user_id is not null and new.user_id <> v_user_id then
    raise exception 'Assessment creator must match the authenticated user'
      using errcode = '42501';
  end if;

  if new.company_id is not null and new.company_id <> v_company_id then
    raise exception 'Assessment company must match the authenticated profile company'
      using errcode = '42501';
  end if;

  new.user_id := v_user_id;
  new.company_id := v_company_id;
  return new;
end;
$$;

-- Ownership is immutable for creators and company admins alike. Privileged
-- service-role or migration maintenance that genuinely must repair ownership is
-- intentionally not given a silent bypass: a controlled migration must disable
-- this named trigger explicitly, perform a reviewed repair, and re-enable it.
create function public.prevent_station_assessment_ownership_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception 'Assessment creator ownership cannot be changed'
      using errcode = '42501';
  end if;

  if new.company_id is distinct from old.company_id then
    raise exception 'Assessment company ownership cannot be changed'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all privileges
on function public.set_station_assessment_ownership() from public;

revoke all privileges
on function public.set_station_assessment_ownership() from anon;

revoke all privileges
on function public.set_station_assessment_ownership() from authenticated;

revoke all privileges
on function public.prevent_station_assessment_ownership_change() from public;

revoke all privileges
on function public.prevent_station_assessment_ownership_change() from anon;

revoke all privileges
on function public.prevent_station_assessment_ownership_change() from authenticated;

create trigger set_station_assessment_ownership
before insert on public.station_assessments
for each row
execute function public.set_station_assessment_ownership();

create trigger prevent_station_assessment_ownership_change
before update of user_id, company_id on public.station_assessments
for each row
execute function public.prevent_station_assessment_ownership_change();

comment on trigger set_station_assessment_ownership
on public.station_assessments is
  'Derives and validates creator/company ownership from auth.uid() and profiles.company_id before RLS checks.';

comment on trigger prevent_station_assessment_ownership_change
on public.station_assessments is
  'Prevents creators, company admins, and ordinary API clients from transferring assessment ownership.';

-- Replace creator-only Module 2 policies with approved company collaboration:
-- all company members read; creators edit/delete their own rows; company admins
-- edit/delete any row in their company; no company can access another company.
drop policy "Users can view own assessments"
on public.station_assessments;

drop policy "Users can create own assessments"
on public.station_assessments;

drop policy "Users can update own assessments"
on public.station_assessments;

drop policy "Users can delete own assessments"
on public.station_assessments;

alter table public.station_assessments enable row level security;

create policy "Company members can view company assessments"
on public.station_assessments
for select
to authenticated
using (
  company_id is not null
  and company_id = public.current_assessment_company_id()
);

create policy "Company members can create own company assessments"
on public.station_assessments
for insert
to authenticated
with check (
  user_id = auth.uid()
  and company_id is not null
  and company_id = public.current_assessment_company_id()
);

create policy "Creators and company admins can update company assessments"
on public.station_assessments
for update
to authenticated
using (
  company_id is not null
  and company_id = public.current_assessment_company_id()
  and (
    user_id = auth.uid()
    or public.current_user_is_company_admin()
  )
)
with check (
  company_id is not null
  and company_id = public.current_assessment_company_id()
  and (
    user_id = auth.uid()
    or public.current_user_is_company_admin()
  )
);

create policy "Creators and company admins can delete company assessments"
on public.station_assessments
for delete
to authenticated
using (
  company_id is not null
  and company_id = public.current_assessment_company_id()
  and (
    user_id = auth.uid()
    or public.current_user_is_company_admin()
  )
);

comment on policy "Company members can view company assessments"
on public.station_assessments is
  'Authenticated users may read assessments only for profiles.company_id; unresolved legacy rows remain hidden.';

comment on policy "Company members can create own company assessments"
on public.station_assessments is
  'New ownership must resolve to auth.uid() and the caller''s authoritative profiles.company_id.';

comment on policy "Creators and company admins can update company assessments"
on public.station_assessments is
  'Normal users update only their own company rows; company admins update any row in their company.';

comment on policy "Creators and company admins can delete company assessments"
on public.station_assessments is
  'Normal users delete only their own company rows; company admins delete any row in their company.';

-- Explicit privileges complement RLS. Clear table-level privileges and any
-- possible legacy ownership-column UPDATE ACLs for every API-facing grantee
-- before granting the authenticated allowlist. The immutability trigger remains
-- an independent second layer and also protects privileged maintenance by default.
revoke all privileges
on table public.station_assessments from public;

revoke all privileges
on table public.station_assessments from anon;

revoke all privileges
on table public.station_assessments from authenticated;

revoke update (user_id, company_id)
on table public.station_assessments from public;

revoke update (user_id, company_id)
on table public.station_assessments from anon;

revoke update (user_id, company_id)
on table public.station_assessments from authenticated;

grant select, insert, delete
on table public.station_assessments to authenticated;

grant update (
  location_name,
  population_density,
  traffic_level,
  registered_vehicle_count,
  nearby_fuel_stations,
  competitor_distance_km,
  road_accessibility,
  commercial_activity,
  residential_activity,
  land_accessibility,
  final_score,
  suitability_category,
  recommendation,
  explanation
)
on public.station_assessments to authenticated;
