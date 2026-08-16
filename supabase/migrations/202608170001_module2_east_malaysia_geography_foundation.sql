-- Module 2 East Malaysia geography foundation.
--
-- This forward migration intentionally installs no boundary data. Geographic
-- validation therefore fails closed as unverified until a later reviewed import
-- activates one complete, licensed Sabah/Sarawak/Labuan boundary dataset.
-- Execute this migration in a transaction-capable migration runner or an
-- explicitly reviewed SQL Editor transaction.

-- Validate the deployed company-assessment foundation before changing schema.
do $$
declare
  v_postgis_schema text;
  v_gis_owner text;
begin
  if exists (
    select 1
    from (
      values ('anon'), ('authenticated'), ('service_role')
    ) as required_role(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role_entry
      where role_entry.rolname = required_role.role_name
    )
  ) then
    raise exception
      'Module 2 geography foundation requires anon, authenticated, and service_role roles';
  end if;

  if pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.fuel_companies') is null
    or pg_catalog.to_regclass('public.station_assessments') is null then
    raise exception
      'Module 2 geography foundation requires profiles, fuel_companies, and station_assessments';
  end if;

  if exists (
    select 1
    from (
      values
        ('profiles', 'user_id'),
        ('profiles', 'company_id'),
        ('profiles', 'role'),
        ('fuel_companies', 'id'),
        ('station_assessments', 'id'),
        ('station_assessments', 'user_id'),
        ('station_assessments', 'company_id'),
        ('station_assessments', 'location_name'),
        ('station_assessments', 'population_density'),
        ('station_assessments', 'traffic_level'),
        ('station_assessments', 'registered_vehicle_count'),
        ('station_assessments', 'nearby_fuel_stations'),
        ('station_assessments', 'competitor_distance_km'),
        ('station_assessments', 'road_accessibility'),
        ('station_assessments', 'commercial_activity'),
        ('station_assessments', 'residential_activity'),
        ('station_assessments', 'land_accessibility'),
        ('station_assessments', 'final_score'),
        ('station_assessments', 'suitability_category'),
        ('station_assessments', 'recommendation'),
        ('station_assessments', 'explanation'),
        ('station_assessments', 'created_at'),
        ('station_assessments', 'updated_at')
    ) as required_column(table_name, column_name)
    where not exists (
      select 1
      from information_schema.columns as existing_column
      where existing_column.table_schema = 'public'
        and existing_column.table_name = required_column.table_name
        and existing_column.column_name = required_column.column_name
    )
  ) then
    raise exception
      'Module 2 geography foundation required columns are missing';
  end if;

  if exists (
    select profile.user_id
    from public.profiles as profile
    group by profile.user_id
    having count(*) > 1
  ) then
    raise exception
      'Module 2 geography foundation requires unique profiles.user_id values';
  end if;

  if exists (
    select 1
    from public.station_assessments as assessment
    where assessment.company_id is null
  ) then
    raise exception
      'Module 2 geography foundation requires every assessment to have company ownership';
  end if;

  if pg_catalog.to_regprocedure(
    'public.current_assessment_company_id()'
  ) is null
    or pg_catalog.to_regprocedure(
      'public.current_user_is_company_admin()'
    ) is null
    or pg_catalog.to_regprocedure(
      'public.set_station_assessment_ownership()'
    ) is null
    or pg_catalog.to_regprocedure(
      'public.prevent_station_assessment_ownership_change()'
    ) is null
    or pg_catalog.to_regprocedure(
      'public.update_updated_at_column()'
    ) is null then
    raise exception
      'Module 2 company-assessment helper functions are incomplete';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_trigger as trigger_entry
    where trigger_entry.tgrelid = 'public.station_assessments'::regclass
      and not trigger_entry.tgisinternal
      and trigger_entry.tgname in (
        'set_station_assessment_ownership',
        'prevent_station_assessment_ownership_change',
        'update_station_assessments_updated_at'
      )
  ) <> 3 then
    raise exception
      'Module 2 company-assessment triggers are incomplete';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_policies as policy_entry
    where policy_entry.schemaname = 'public'
      and policy_entry.tablename = 'station_assessments'
  ) <> 4
    or exists (
      select 1
      from (
        values
          ('Company members can view company assessments'),
          ('Company members can create own company assessments'),
          ('Creators and company admins can update company assessments'),
          ('Creators and company admins can delete company assessments')
      ) as required_policy(policy_name)
      where not exists (
        select 1
        from pg_catalog.pg_policies as existing_policy
        where existing_policy.schemaname = 'public'
          and existing_policy.tablename = 'station_assessments'
          and existing_policy.policyname = required_policy.policy_name
      )
    ) then
    raise exception
      'Module 2 company-assessment policy matrix differs from the required foundation';
  end if;

  if exists (
    select 1
    from (
      values
        ('station_assessments_user_id_idx'),
        ('station_assessments_company_id_idx'),
        ('station_assessments_company_created_at_idx')
    ) as required_index(index_name)
    where pg_catalog.to_regclass(
      pg_catalog.format('public.%I', required_index.index_name)
    ) is null
  ) then
    raise exception
      'Module 2 company-assessment indexes are incomplete';
  end if;

  if pg_catalog.to_regclass(
    'public.east_malaysia_boundary_datasets'
  ) is not null
    or pg_catalog.to_regclass(
      'public.east_malaysia_territory_boundaries'
    ) is not null then
    raise exception
      'Module 2 geography boundary tables already exist';
  end if;

  if pg_catalog.to_regprocedure(
    'public.validate_east_malaysia_site(double precision,double precision,smallint)'
  ) is not null then
    raise exception
      'Module 2 geography validator already exists';
  end if;

  if exists (
    select 1
    from information_schema.columns as existing_column
    where existing_column.table_schema = 'public'
      and existing_column.table_name = 'station_assessments'
      and existing_column.column_name in (
        'site_location',
        'analysis_radius_km',
        'geographic_validation_status',
        'confirmed_territory',
        'boundary_dataset_id',
        'geographically_validated_at'
      )
  ) then
    raise exception
      'Module 2 geography assessment columns already exist';
  end if;

  if exists (
    select 1
    from (
      values
        ('east_malaysia_boundary_datasets_one_active_idx'),
        ('east_malaysia_territory_boundaries_boundary_gist_idx'),
        ('station_assessments_site_location_gist_idx')
    ) as target_index(index_name)
    where pg_catalog.to_regclass(
      pg_catalog.format('public.%I', target_index.index_name)
    ) is not null
  ) then
    raise exception
      'Module 2 geography target indexes already exist';
  end if;

  select namespace.nspname
  into v_postgis_schema
  from pg_catalog.pg_extension as extension_entry
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = extension_entry.extnamespace
  where extension_entry.extname = 'postgis';

  if v_postgis_schema is not null and v_postgis_schema <> 'gis' then
    raise exception
      'PostGIS is already installed in schema %, expected gis; relocation is not permitted',
      v_postgis_schema;
  end if;

  if exists (
    select 1
    from pg_catalog.pg_namespace as namespace
    where namespace.nspname = 'gis'
  ) then
    select pg_catalog.pg_get_userbyid(namespace.nspowner)
    into v_gis_owner
    from pg_catalog.pg_namespace as namespace
    where namespace.nspname = 'gis';

    if v_gis_owner is distinct from current_user then
      raise exception
        'Existing gis schema owner is %, expected current migration owner %',
        v_gis_owner,
        current_user;
    end if;

    if exists (
      select 1
      from pg_catalog.pg_namespace as namespace
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          namespace.nspacl,
          pg_catalog.acldefault('n', namespace.nspowner)
        )
      ) as schema_acl
      where namespace.nspname = 'gis'
        and schema_acl.privilege_type = 'CREATE'
        and schema_acl.grantee <> namespace.nspowner
    ) then
      raise exception
        'Existing gis schema grants CREATE to a non-owner role';
    end if;

    if v_postgis_schema is null
      and (
        exists (
          select 1
          from pg_catalog.pg_class as class_entry
          join pg_catalog.pg_namespace as namespace
            on namespace.oid = class_entry.relnamespace
          where namespace.nspname = 'gis'
        )
        or exists (
          select 1
          from pg_catalog.pg_proc as procedure_entry
          join pg_catalog.pg_namespace as namespace
            on namespace.oid = procedure_entry.pronamespace
          where namespace.nspname = 'gis'
        )
        or exists (
          select 1
          from pg_catalog.pg_type as type_entry
          join pg_catalog.pg_namespace as namespace
            on namespace.oid = type_entry.typnamespace
          where namespace.nspname = 'gis'
        )
      ) then
      raise exception
        'Existing gis schema is not empty and is not owned by PostGIS';
    end if;
  end if;
end;
$$;

-- Capture all pre-existing assessment values that this additive migration must
-- preserve. The temporary snapshot is verified and dropped before completion.
create temporary table module2_geography_assessment_snapshot
on commit preserve rows
as
select
  assessment.id,
  assessment.user_id,
  assessment.company_id,
  assessment.location_name,
  assessment.population_density,
  assessment.traffic_level,
  assessment.registered_vehicle_count,
  assessment.nearby_fuel_stations,
  assessment.competitor_distance_km,
  assessment.road_accessibility,
  assessment.commercial_activity,
  assessment.residential_activity,
  assessment.land_accessibility,
  assessment.final_score,
  assessment.suitability_category,
  assessment.recommendation,
  assessment.explanation,
  assessment.created_at,
  assessment.updated_at
from public.station_assessments as assessment;

create schema if not exists gis;

create extension if not exists postgis with schema gis;

do $$
declare
  v_postgis_schema text;
begin
  select namespace.nspname
  into v_postgis_schema
  from pg_catalog.pg_extension as extension_entry
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = extension_entry.extnamespace
  where extension_entry.extname = 'postgis';

  if v_postgis_schema is distinct from 'gis' then
    raise exception
      'PostGIS installation schema is %, expected gis',
      coalesce(v_postgis_schema, '<missing>');
  end if;
end;
$$;

-- The API roles never receive CREATE. Authenticated needs only schema USAGE so
-- PostgREST can return station_assessments rows containing a geography column.
revoke all privileges on schema gis from public;
revoke all privileges on schema gis from anon;
revoke all privileges on schema gis from authenticated;
revoke all privileges on schema gis from service_role;
grant usage on schema gis to authenticated, service_role;

create table public.east_malaysia_boundary_datasets (
  id uuid primary key default gen_random_uuid(),
  source_provider text not null,
  source_reference text not null,
  source_version text not null,
  source_release_date date null,
  licence text not null,
  attribution text not null,
  imported_at timestamptz not null default now(),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint east_malaysia_boundary_dataset_provider_not_blank
    check (pg_catalog.btrim(source_provider) <> ''),
  constraint east_malaysia_boundary_dataset_reference_not_blank
    check (pg_catalog.btrim(source_reference) <> ''),
  constraint east_malaysia_boundary_dataset_version_not_blank
    check (pg_catalog.btrim(source_version) <> ''),
  constraint east_malaysia_boundary_dataset_licence_not_blank
    check (pg_catalog.btrim(licence) <> ''),
  constraint east_malaysia_boundary_dataset_attribution_not_blank
    check (pg_catalog.btrim(attribution) <> ''),
  constraint east_malaysia_boundary_dataset_source_unique
    unique (source_provider, source_reference, source_version)
);

create unique index east_malaysia_boundary_datasets_one_active_idx
on public.east_malaysia_boundary_datasets ((is_active))
where is_active;

create table public.east_malaysia_territory_boundaries (
  id uuid primary key default gen_random_uuid(),
  dataset_id uuid not null,
  territory text not null,
  boundary gis.geometry(MultiPolygon, 4326) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint east_malaysia_territory_boundary_dataset_fkey
    foreign key (dataset_id)
    references public.east_malaysia_boundary_datasets(id)
    on delete restrict,
  constraint east_malaysia_territory_boundary_value_check
    check (territory in ('sabah', 'sarawak', 'labuan')),
  constraint east_malaysia_territory_boundary_dataset_unique
    unique (dataset_id, territory),
  constraint east_malaysia_territory_boundary_not_empty
    check (not gis.st_isempty(boundary)),
  constraint east_malaysia_territory_boundary_valid
    check (gis.st_isvalid(boundary)),
  constraint east_malaysia_territory_boundary_two_dimensional
    check (gis.st_ndims(boundary) = 2),
  constraint east_malaysia_territory_boundary_srid
    check (gis.st_srid(boundary) = 4326),
  constraint east_malaysia_territory_boundary_multipolygon
    check (gis.st_geometrytype(boundary) = 'ST_MultiPolygon')
);

create index east_malaysia_territory_boundaries_boundary_gist_idx
on public.east_malaysia_territory_boundaries
using gist (boundary);

alter table public.east_malaysia_boundary_datasets
enable row level security;

alter table public.east_malaysia_territory_boundaries
enable row level security;

-- No API-facing role receives direct table access. A later reviewed owner-level
-- import transaction will populate and activate licensed reference data.
revoke all privileges
on table public.east_malaysia_boundary_datasets
from public, anon, authenticated, service_role;

revoke all privileges
on table public.east_malaysia_territory_boundaries
from public, anon, authenticated, service_role;

create trigger update_east_malaysia_boundary_datasets_updated_at
before update on public.east_malaysia_boundary_datasets
for each row
execute function public.update_updated_at_column();

create trigger update_east_malaysia_territory_boundaries_updated_at
before update on public.east_malaysia_territory_boundaries
for each row
execute function public.update_updated_at_column();

alter table public.station_assessments
add column site_location gis.geography(Point, 4326) null,
add column analysis_radius_km smallint null,
add column geographic_validation_status text null,
add column confirmed_territory text null,
add column boundary_dataset_id uuid null,
add column geographically_validated_at timestamptz null;

alter table public.station_assessments
add constraint station_assessments_boundary_dataset_fkey
foreign key (boundary_dataset_id)
references public.east_malaysia_boundary_datasets(id)
on delete restrict;

-- Existing rows become explicitly legacy-unverified without changing their
-- historical updated_at values. New legacy-form inserts default to unverified.
alter table public.station_assessments
disable trigger update_station_assessments_updated_at;

update public.station_assessments as assessment
set geographic_validation_status = 'legacy_unverified'
from pg_temp.module2_geography_assessment_snapshot as snapshot
where snapshot.id = assessment.id;

alter table public.station_assessments
alter column geographic_validation_status set default 'unverified';

alter table public.station_assessments
alter column geographic_validation_status set not null;

alter table public.station_assessments
enable trigger update_station_assessments_updated_at;

alter table public.station_assessments
add constraint station_assessments_analysis_radius_check
  check (analysis_radius_km is null or analysis_radius_km in (3, 5, 10)),
add constraint station_assessments_confirmed_territory_check
  check (
    confirmed_territory is null
    or confirmed_territory in ('sabah', 'sarawak', 'labuan')
  ),
add constraint station_assessments_site_coordinate_check
  check (
    site_location is null
    or (
      not gis.st_isempty(site_location::gis.geometry)
      and gis.st_x(site_location::gis.geometry) between -180 and 180
      and gis.st_y(site_location::gis.geometry) between -90 and 90
      and gis.st_x(site_location::gis.geometry)
        <> 'NaN'::double precision
      and gis.st_y(site_location::gis.geometry)
        <> 'NaN'::double precision
    )
  ),
add constraint station_assessments_geographic_status_check
  check (
    geographic_validation_status in (
      'legacy_unverified',
      'unverified',
      'inside',
      'outside',
      'boundary_review_required'
    )
  ),
add constraint station_assessments_geographic_state_check
  check (
    case geographic_validation_status
      when 'legacy_unverified' then
        site_location is null
        and analysis_radius_km is null
        and confirmed_territory is null
        and boundary_dataset_id is null
        and geographically_validated_at is null
      when 'unverified' then
        (site_location is null) = (analysis_radius_km is null)
        and confirmed_territory is null
        and boundary_dataset_id is null
        and geographically_validated_at is null
      when 'inside' then
        site_location is not null
        and analysis_radius_km is not null
        and confirmed_territory is not null
        and boundary_dataset_id is not null
        and geographically_validated_at is not null
      when 'outside' then
        site_location is not null
        and analysis_radius_km is not null
        and confirmed_territory is null
        and boundary_dataset_id is not null
        and geographically_validated_at is not null
      when 'boundary_review_required' then
        site_location is not null
        and analysis_radius_km is not null
        and confirmed_territory is null
        and boundary_dataset_id is not null
        and geographically_validated_at is not null
      else false
    end
  );

create index station_assessments_site_location_gist_idx
on public.station_assessments
using gist (site_location);

create function public.validate_east_malaysia_site(
  p_latitude double precision,
  p_longitude double precision,
  p_analysis_radius_km smallint
)
returns table (
  validation_status text,
  confirmed_territory text,
  boundary_dataset_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_active_dataset_count integer;
  v_dataset_id uuid;
  v_boundary_count integer;
  v_distinct_territory_count integer;
  v_boundaries_valid boolean;
  v_point gis.geometry(Point, 4326);
  v_match_count integer;
  v_matched_territory text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required for geographic validation'
      using errcode = '42501';
  end if;

  select profile.company_id
  into v_company_id
  from public.profiles as profile
  where profile.user_id = v_user_id;

  if not found or v_company_id is null then
    raise exception
      'An authoritative company membership is required for geographic validation'
      using errcode = '42501';
  end if;

  if p_latitude is null
    or p_latitude = 'NaN'::double precision
    or p_latitude < -90
    or p_latitude > 90 then
    raise exception 'Latitude must be finite and between -90 and 90 degrees'
      using errcode = '22023';
  end if;

  if p_longitude is null
    or p_longitude = 'NaN'::double precision
    or p_longitude < -180
    or p_longitude > 180 then
    raise exception 'Longitude must be finite and between -180 and 180 degrees'
      using errcode = '22023';
  end if;

  if p_analysis_radius_km is null
    or p_analysis_radius_km not in (3, 5, 10) then
    raise exception 'Analysis radius must be exactly 3, 5, or 10 kilometres'
      using errcode = '22023';
  end if;

  v_point := gis.st_setsrid(
    gis.st_makepoint(p_longitude, p_latitude),
    4326
  )::gis.geometry(Point, 4326);

  select
    pg_catalog.count(*)::integer,
    (pg_catalog.array_agg(dataset.id order by dataset.id))[1]
  into
    v_active_dataset_count,
    v_dataset_id
  from public.east_malaysia_boundary_datasets as dataset
  where dataset.is_active;

  if v_active_dataset_count = 0 then
    return query
    select
      'unverified'::text,
      null::text,
      null::uuid;
    return;
  end if;

  if v_active_dataset_count <> 1 then
    raise exception 'Active East Malaysia boundary dataset is ambiguous'
      using errcode = '22000';
  end if;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(distinct boundary_entry.territory)::integer,
    coalesce(
      pg_catalog.bool_and(
        not gis.st_isempty(boundary_entry.boundary)
        and gis.st_isvalid(boundary_entry.boundary)
        and gis.st_ndims(boundary_entry.boundary) = 2
        and gis.st_srid(boundary_entry.boundary) = 4326
        and gis.st_geometrytype(boundary_entry.boundary) = 'ST_MultiPolygon'
      ),
      false
    )
  into
    v_boundary_count,
    v_distinct_territory_count,
    v_boundaries_valid
  from public.east_malaysia_territory_boundaries as boundary_entry
  where boundary_entry.dataset_id = v_dataset_id;

  if v_boundary_count <> 3
    or v_distinct_territory_count <> 3
    or not v_boundaries_valid then
    raise exception
      'Active East Malaysia boundary dataset is incomplete or invalid'
      using errcode = '22000';
  end if;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.min(boundary_entry.territory)
  into
    v_match_count,
    v_matched_territory
  from public.east_malaysia_territory_boundaries as boundary_entry
  where boundary_entry.dataset_id = v_dataset_id
    and gis.st_covers(boundary_entry.boundary, v_point);

  if v_match_count > 1 then
    raise exception 'East Malaysia boundary match is ambiguous'
      using errcode = '22000';
  end if;

  if v_match_count = 1 then
    return query
    select
      'inside'::text,
      v_matched_territory,
      v_dataset_id;
    return;
  end if;

  return query
  select
    'outside'::text,
    null::text,
    v_dataset_id;
end;
$$;

revoke all privileges
on function public.validate_east_malaysia_site(
  double precision,
  double precision,
  smallint
)
from public, anon, authenticated, service_role;

grant execute
on function public.validate_east_malaysia_site(
  double precision,
  double precision,
  smallint
)
to authenticated, service_role;

comment on function public.validate_east_malaysia_site(
  double precision,
  double precision,
  smallint
) is
  'Validates a point against the single complete active East Malaysia boundary dataset. Empty reference data returns unverified; the function never trusts client-supplied territory or Auth metadata and does not write assessments.';

-- Remove table-level INSERT so newly added authoritative columns cannot inherit
-- broad write access. Clear possible legacy column ACLs before granting the
-- exact legacy repository payload, including its session-derived user_id.
revoke insert on table public.station_assessments
from public, anon, authenticated;

revoke insert (
  id,
  user_id,
  company_id,
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
  explanation,
  created_at,
  updated_at,
  site_location,
  analysis_radius_km,
  geographic_validation_status,
  confirmed_territory,
  boundary_dataset_id,
  geographically_validated_at
)
on table public.station_assessments
from public, anon, authenticated;

grant insert (
  user_id,
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
on table public.station_assessments
to authenticated;

-- Rebuild UPDATE privileges from a deterministic empty baseline. Table-level
-- privileges and every possible legacy column ACL are independent in PostgreSQL,
-- so both layers must be cleared before restoring the approved allowlist.
revoke update on table public.station_assessments
from public, anon, authenticated;

revoke update (
  id,
  user_id,
  company_id,
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
  explanation,
  created_at,
  updated_at,
  site_location,
  analysis_radius_km,
  geographic_validation_status,
  confirmed_territory,
  boundary_dataset_id,
  geographically_validated_at
)
on table public.station_assessments
from public, anon, authenticated;

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
on table public.station_assessments
to authenticated;

-- Verify that the additive rollout preserved every original assessment value
-- and applied only the explicit legacy-unverified state.
do $$
begin
  if (
    select count(*)
    from pg_temp.module2_geography_assessment_snapshot
  ) <> (
    select count(*)
    from public.station_assessments
  ) then
    raise exception
      'Module 2 geography rollout changed the assessment row count';
  end if;

  if exists (
    select 1
    from pg_temp.module2_geography_assessment_snapshot as snapshot
    full join public.station_assessments as assessment
      on assessment.id = snapshot.id
    where snapshot.id is null
      or assessment.id is null
      or row(
        snapshot.user_id,
        snapshot.company_id,
        snapshot.location_name,
        snapshot.population_density,
        snapshot.traffic_level,
        snapshot.registered_vehicle_count,
        snapshot.nearby_fuel_stations,
        snapshot.competitor_distance_km,
        snapshot.road_accessibility,
        snapshot.commercial_activity,
        snapshot.residential_activity,
        snapshot.land_accessibility,
        snapshot.final_score,
        snapshot.suitability_category,
        snapshot.recommendation,
        snapshot.explanation,
        snapshot.created_at,
        snapshot.updated_at
      ) is distinct from row(
        assessment.user_id,
        assessment.company_id,
        assessment.location_name,
        assessment.population_density,
        assessment.traffic_level,
        assessment.registered_vehicle_count,
        assessment.nearby_fuel_stations,
        assessment.competitor_distance_km,
        assessment.road_accessibility,
        assessment.commercial_activity,
        assessment.residential_activity,
        assessment.land_accessibility,
        assessment.final_score,
        assessment.suitability_category,
        assessment.recommendation,
        assessment.explanation,
        assessment.created_at,
        assessment.updated_at
      )
  ) then
    raise exception
      'Module 2 geography rollout changed legacy assessment values or timestamps';
  end if;

  if exists (
    select 1
    from pg_temp.module2_geography_assessment_snapshot as snapshot
    join public.station_assessments as assessment
      on assessment.id = snapshot.id
    where assessment.geographic_validation_status <> 'legacy_unverified'
      or assessment.site_location is not null
      or assessment.analysis_radius_km is not null
      or assessment.confirmed_territory is not null
      or assessment.boundary_dataset_id is not null
      or assessment.geographically_validated_at is not null
  ) then
    raise exception
      'Module 2 geography rollout assigned a geographic claim to a legacy assessment';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class as class_entry
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        class_entry.relacl,
        pg_catalog.acldefault('r', class_entry.relowner)
      )
    ) as table_acl
    where class_entry.oid = 'public.station_assessments'::regclass
      and table_acl.grantee = 0
      and table_acl.privilege_type = 'UPDATE'
  )
    or pg_catalog.has_table_privilege(
      'anon',
      'public.station_assessments',
      'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated',
      'public.station_assessments',
      'UPDATE'
    ) then
    raise exception
      'Module 2 geography foundation left a table-level assessment UPDATE privilege';
  end if;

  if exists (
    select 1
    from (
      values
        ('location_name'),
        ('population_density'),
        ('traffic_level'),
        ('registered_vehicle_count'),
        ('nearby_fuel_stations'),
        ('competitor_distance_km'),
        ('road_accessibility'),
        ('commercial_activity'),
        ('residential_activity'),
        ('land_accessibility'),
        ('final_score'),
        ('suitability_category'),
        ('recommendation'),
        ('explanation')
    ) as approved_update(column_name)
    where not pg_catalog.has_column_privilege(
      'authenticated',
      'public.station_assessments',
      approved_update.column_name,
      'UPDATE'
    )
  ) then
    raise exception
      'Module 2 geography foundation did not restore the approved assessment UPDATE allowlist';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
      and attribute_entry.attname not in (
        'location_name',
        'population_density',
        'traffic_level',
        'registered_vehicle_count',
        'nearby_fuel_stations',
        'competitor_distance_km',
        'road_accessibility',
        'commercial_activity',
        'residential_activity',
        'land_accessibility',
        'final_score',
        'suitability_category',
        'recommendation',
        'explanation'
      )
      and pg_catalog.has_column_privilege(
        'authenticated',
        'public.station_assessments',
        attribute_entry.attname,
        'UPDATE'
      )
  ) then
    raise exception
      'Module 2 geography foundation exposed a protected assessment UPDATE column';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
      and pg_catalog.has_column_privilege(
        'anon',
        'public.station_assessments',
        attribute_entry.attname,
        'UPDATE'
      )
  ) then
    raise exception
      'Module 2 geography foundation left anon assessment UPDATE access';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute as attribute_entry
    cross join lateral pg_catalog.aclexplode(
      coalesce(attribute_entry.attacl, '{}'::aclitem[])
    ) as column_acl
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
      and column_acl.grantee = 0
      and column_acl.privilege_type = 'UPDATE'
  ) then
    raise exception
      'Module 2 geography foundation left PUBLIC assessment column UPDATE access';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_namespace as namespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        namespace.nspacl,
        pg_catalog.acldefault('n', namespace.nspowner)
      )
    ) as schema_acl
    where namespace.nspname = 'gis'
      and schema_acl.privilege_type = 'CREATE'
      and schema_acl.grantee <> namespace.nspowner
  ) then
    raise exception
      'Module 2 geography foundation granted CREATE on gis to a non-owner role';
  end if;

  if not pg_catalog.has_schema_privilege(
    'authenticated',
    'gis',
    'USAGE'
  )
    or pg_catalog.has_schema_privilege(
      'authenticated',
      'gis',
      'CREATE'
    )
    or pg_catalog.has_schema_privilege('anon', 'gis', 'USAGE')
    or pg_catalog.has_schema_privilege('anon', 'gis', 'CREATE') then
    raise exception
      'Module 2 geography gis schema privileges differ from the minimum required ACL';
  end if;
end;
$$;

drop table pg_temp.module2_geography_assessment_snapshot;
