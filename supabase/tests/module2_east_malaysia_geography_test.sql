-- Module 2 East Malaysia geography foundation tests.
--
-- Run only in an isolated Supabase/PostgreSQL verification environment after
-- applying the geography foundation migration. Every polygon and identity in
-- this file is synthetic test data and does not represent a real administrative
-- boundary, user, company, or production identifier.

begin;

-- Some SQL Editor sessions materialize the real pg_temp namespace only after
-- the first temporary object is created. This table initializes that namespace
-- before pg_temp helpers are created; the final rollback removes it.
create temporary table module2_geography_test_session_init (
  initialized boolean not null default true
)
on commit drop;

create function pg_temp.assert_true(
  condition boolean,
  message text
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if condition is distinct from true then
    raise exception 'Module 2 geography assertion failed: %', message;
  end if;
end;
$$;

create function pg_temp.insert_assessment(
  p_location_name text,
  p_user_id uuid
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_assessment_id uuid;
begin
  insert into public.station_assessments (
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
  values (
    p_user_id,
    p_location_name,
    100,
    3,
    1000,
    2,
    3,
    3,
    3,
    3,
    3,
    50,
    'Synthetic moderate',
    'Synthetic recommendation',
    'Synthetic explanation'
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$$;

-- Resolve the actual numbered session temp schema before
-- granting helper access. pg_temp itself is only an alias and cannot be used as
-- the target of these GRANT statements in every SQL Editor session.
do $$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception
      'Module 2 geography test temporary schema was not initialized';
  end if;

  execute pg_catalog.format(
    'grant usage on schema %I to authenticated, anon, service_role',
    v_temp_schema
  );

  execute pg_catalog.format(
    'grant execute on function %I.assert_true(boolean, text) to authenticated, anon, service_role',
    v_temp_schema
  );

  execute pg_catalog.format(
    'grant execute on function %I.insert_assessment(text, uuid) to authenticated',
    v_temp_schema
  );
end;
$$;

-- Preserve the exact post-migration state of every pre-existing assessment.
-- The migration itself performs a pre/post legacy snapshot; this test also
-- proves its synthetic operations never mutate those original rows.
create temporary table module2_geography_original_assessments
on commit drop
as
select
  assessment.id,
  pg_catalog.to_jsonb(assessment) as row_data
from public.station_assessments as assessment;

select pg_temp.assert_true(
  not exists (
    select 1
    from public.station_assessments as assessment
    where assessment.geographic_validation_status <> 'legacy_unverified'
      or assessment.site_location is not null
      or assessment.analysis_radius_km is not null
      or assessment.confirmed_territory is not null
      or assessment.boundary_dataset_id is not null
      or assessment.geographically_validated_at is not null
  ),
  'pre-existing assessments must be legacy_unverified without a geographic claim'
);

-- Extension placement, schema ACL, protected table ACL, and type availability.
select pg_temp.assert_true(
  (
    select namespace.nspname = 'gis'
    from pg_catalog.pg_extension as extension_entry
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = extension_entry.extnamespace
    where extension_entry.extname = 'postgis'
  ),
  'PostGIS must exist in the dedicated gis schema'
);

select pg_temp.assert_true(
  pg_catalog.to_regtype('gis.geometry') is not null
    and pg_catalog.to_regtype('gis.geography') is not null,
  'PostGIS geometry and geography types must be available in gis'
);

select pg_temp.assert_true(
  pg_catalog.has_schema_privilege('authenticated', 'gis', 'USAGE')
    and not pg_catalog.has_schema_privilege(
      'authenticated',
      'gis',
      'CREATE'
    )
    and not pg_catalog.has_schema_privilege('anon', 'gis', 'USAGE')
    and not pg_catalog.has_schema_privilege('anon', 'gis', 'CREATE')
    and pg_catalog.has_schema_privilege('service_role', 'gis', 'USAGE')
    and not pg_catalog.has_schema_privilege(
      'service_role',
      'gis',
      'CREATE'
    ),
  'gis schema must expose only the minimum required USAGE privileges'
);

select pg_temp.assert_true(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'public.station_assessments',
    'INSERT'
  ),
  'authenticated must not retain table-level assessment INSERT'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from (
      values
        ('user_id'),
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
    ) as allowed_insert(column_name)
    where not pg_catalog.has_column_privilege(
      'authenticated',
      'public.station_assessments',
      allowed_insert.column_name,
      'INSERT'
    )
  ),
  'authenticated must retain the legacy repository INSERT allowlist'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from (
      values
        ('id'),
        ('company_id'),
        ('created_at'),
        ('updated_at'),
        ('site_location'),
        ('analysis_radius_km'),
        ('geographic_validation_status'),
        ('confirmed_territory'),
        ('boundary_dataset_id'),
        ('geographically_validated_at')
    ) as protected_insert(column_name)
    where pg_catalog.has_column_privilege(
      'authenticated',
      'public.station_assessments',
      protected_insert.column_name,
      'INSERT'
    )
  )
    and not exists (
      select 1
      from (
        values
          ('id'),
          ('user_id'),
          ('company_id'),
          ('created_at'),
          ('updated_at'),
          ('site_location'),
          ('analysis_radius_km'),
          ('geographic_validation_status'),
          ('confirmed_territory'),
          ('boundary_dataset_id'),
          ('geographically_validated_at')
      ) as protected_update(column_name)
      where pg_catalog.has_column_privilege(
        'authenticated',
        'public.station_assessments',
        protected_update.column_name,
        'UPDATE'
      )
    ),
  'authenticated must not write authoritative ownership or geography columns'
);

select pg_temp.assert_true(
  not exists (
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
    ) as allowed_update(column_name)
    where not pg_catalog.has_column_privilege(
      'authenticated',
      'public.station_assessments',
      allowed_update.column_name,
      'UPDATE'
    )
  ),
  'authenticated must retain the existing 14-column UPDATE allowlist'
);

select pg_temp.assert_true(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.validate_east_malaysia_site(double precision,double precision,smallint)',
    'EXECUTE'
  )
    and pg_catalog.has_function_privilege(
      'service_role',
      'public.validate_east_malaysia_site(double precision,double precision,smallint)',
      'EXECUTE'
    )
    and not pg_catalog.has_function_privilege(
      'anon',
      'public.validate_east_malaysia_site(double precision,double precision,smallint)',
      'EXECUTE'
    ),
  'validator EXECUTE must be limited to authenticated and service_role'
);

do $$
declare
  v_check record;
  v_has_privilege boolean;
begin
  for v_check in
    select
      checked_role.role_name,
      boundary_table.table_name,
      checked_privilege.privilege_name
    from (
      values ('PUBLIC'), ('anon'), ('authenticated'), ('service_role')
    ) as checked_role(role_name)
    cross join (
      values
        ('public.east_malaysia_boundary_datasets'),
        ('public.east_malaysia_territory_boundaries')
    ) as boundary_table(table_name)
    cross join (
      values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')
    ) as checked_privilege(privilege_name)
  loop
    if v_check.role_name = 'PUBLIC' then
      select exists (
        select 1
        from pg_catalog.pg_class as relation
        cross join lateral pg_catalog.aclexplode(
          coalesce(
            relation.relacl,
            pg_catalog.acldefault('r', relation.relowner)
          )
        ) as acl
        where relation.oid = pg_catalog.to_regclass(v_check.table_name)
          and acl.grantee = 0
          and acl.privilege_type = v_check.privilege_name
      )
      into v_has_privilege;
    else
      v_has_privilege := pg_catalog.has_table_privilege(
        v_check.role_name,
        v_check.table_name,
        v_check.privilege_name
      );
    end if;

    if v_has_privilege then
      raise exception
        'Boundary ACL assertion failed: role %, table %, privilege % must be denied',
        v_check.role_name,
        v_check.table_name,
        v_check.privilege_name;
    end if;
  end loop;
end;
$$;

select pg_temp.assert_true(
  (
    select pg_catalog.bool_and(relation.relrowsecurity)
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.east_malaysia_boundary_datasets'::regclass,
      'public.east_malaysia_territory_boundaries'::regclass
    )
  )
    and not exists (
      select 1
      from pg_catalog.pg_policy as policy
      where policy.polrelid in (
        'public.east_malaysia_boundary_datasets'::regclass,
        'public.east_malaysia_territory_boundaries'::regclass
      )
    ),
  'boundary tables must keep RLS enabled with no API policies'
);

-- Synthetic identities and companies. auth.users creation invokes the existing
-- profile trigger, after which authoritative company membership is assigned.
insert into public.fuel_companies (
  id,
  company_code,
  company_name
)
values
  (
    '31000000-0000-0000-0000-000000000001',
    'MODULE2_GEO_TEST_A',
    'Module 2 Geography Test Company A'
  ),
  (
    '31000000-0000-0000-0000-000000000002',
    'MODULE2_GEO_TEST_B',
    'Module 2 Geography Test Company B'
  );

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values
  (
    '32000000-0000-0000-0000-000000000101',
    'module2-geo-user-a1@example.invalid',
    '{"full_name":"Module 2 Geography User A1"}'::jsonb
  ),
  (
    '32000000-0000-0000-0000-000000000102',
    'module2-geo-user-a2@example.invalid',
    '{"full_name":"Module 2 Geography User A2"}'::jsonb
  ),
  (
    '32000000-0000-0000-0000-000000000103',
    'module2-geo-admin-a@example.invalid',
    '{"full_name":"Module 2 Geography Admin A"}'::jsonb
  ),
  (
    '32000000-0000-0000-0000-000000000201',
    'module2-geo-user-b@example.invalid',
    '{"full_name":"Module 2 Geography User B"}'::jsonb
  ),
  (
    '32000000-0000-0000-0000-000000000301',
    'module2-geo-no-company@example.invalid',
    '{"full_name":"Module 2 Geography No Company"}'::jsonb
  );

update public.profiles
set
  company_id = '31000000-0000-0000-0000-000000000001',
  role = case
    when user_id = '32000000-0000-0000-0000-000000000103'
      then 'company_admin'
    else 'company_user'
  end
where user_id in (
  '32000000-0000-0000-0000-000000000101',
  '32000000-0000-0000-0000-000000000102',
  '32000000-0000-0000-0000-000000000103'
);

update public.profiles
set
  company_id = '31000000-0000-0000-0000-000000000002',
  role = 'company_user'
where user_id = '32000000-0000-0000-0000-000000000201';

-- With no active boundary dataset, a valid authenticated company member gets
-- exactly one unverified result and no authoritative territory or dataset.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

select pg_temp.assert_true(
  (
    select count(*) = 1
      and pg_catalog.bool_and(validation.validation_status = 'unverified')
      and pg_catalog.bool_and(validation.confirmed_territory is null)
      and pg_catalog.bool_and(validation.boundary_dataset_id is null)
    from public.validate_east_malaysia_site(
      5::double precision,
      5::double precision,
      3::smallint
    ) as validation
  ),
  'empty boundary data must fail closed as unverified'
);

reset role;

-- An active but incomplete synthetic dataset is a data-integrity failure, not
-- an outside or unverified geographic claim.
insert into public.east_malaysia_boundary_datasets (
  id,
  source_provider,
  source_reference,
  source_version,
  licence,
  attribution,
  is_active
)
values (
  '33000000-0000-0000-0000-000000000001',
  'Synthetic test provider',
  'https://example.invalid/module2-geography/incomplete',
  'synthetic-incomplete-v1',
  'Synthetic test-only licence',
  'Synthetic test data; not a real boundary',
  true
);

insert into public.east_malaysia_territory_boundaries (
  dataset_id,
  territory,
  boundary
)
values
  (
    '33000000-0000-0000-0000-000000000001',
    'sabah',
    gis.st_geomfromtext(
      'MULTIPOLYGON(((0 0,10 0,10 10,0 10,0 0)))',
      4326
    )::gis.geometry(MultiPolygon, 4326)
  ),
  (
    '33000000-0000-0000-0000-000000000001',
    'sarawak',
    gis.st_geomfromtext(
      'MULTIPOLYGON(((20 0,30 0,30 10,20 10,20 0)))',
      4326
    )::gis.geometry(MultiPolygon, 4326)
  );

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

do $$
begin
  perform * from public.validate_east_malaysia_site(
    null::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected null latitude to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    null::double precision,
    3::smallint
  );
  raise exception 'Expected null longitude to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    null::smallint
  );
  raise exception 'Expected null analysis radius to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform *
  from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected incomplete active boundary dataset to fail';
exception
  when sqlstate '22000' then null;
end;
$$;

reset role;

update public.east_malaysia_boundary_datasets
set is_active = false
where id = '33000000-0000-0000-0000-000000000001';

-- One complete active synthetic dataset. The Labuan-labelled fixture contains
-- two polygon components solely to test MultiPolygon/multi-island handling.
insert into public.east_malaysia_boundary_datasets (
  id,
  source_provider,
  source_reference,
  source_version,
  source_release_date,
  licence,
  attribution,
  is_active
)
values (
  '33000000-0000-0000-0000-000000000002',
  'Synthetic test provider',
  'https://example.invalid/module2-geography/complete',
  'synthetic-complete-v1',
  date '2026-01-01',
  'Synthetic test-only licence',
  'Synthetic test data; not a real boundary',
  true
);

insert into public.east_malaysia_territory_boundaries (
  id,
  dataset_id,
  territory,
  boundary
)
values
  (
    '34000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000002',
    'sabah',
    gis.st_geomfromtext(
      'MULTIPOLYGON(((0 0,10 0,10 10,0 10,0 0)))',
      4326
    )::gis.geometry(MultiPolygon, 4326)
  ),
  (
    '34000000-0000-0000-0000-000000000002',
    '33000000-0000-0000-0000-000000000002',
    'sarawak',
    gis.st_geomfromtext(
      'MULTIPOLYGON(((20 0,30 0,30 10,20 10,20 0)))',
      4326
    )::gis.geometry(MultiPolygon, 4326)
  ),
  (
    '34000000-0000-0000-0000-000000000003',
    '33000000-0000-0000-0000-000000000002',
    'labuan',
    gis.st_geomfromtext(
      'MULTIPOLYGON(((40 0,42 0,42 2,40 2,40 0)),((44 0,46 0,46 2,44 2,44 0)))',
      4326
    )::gis.geometry(MultiPolygon, 4326)
  );

select pg_temp.assert_true(
  gis.st_numgeometries(
    (
      select boundary_entry.boundary
      from public.east_malaysia_territory_boundaries as boundary_entry
      where boundary_entry.dataset_id =
        '33000000-0000-0000-0000-000000000002'
        and boundary_entry.territory = 'labuan'
    )
  ) = 2,
  'synthetic Labuan MultiPolygon must contain two polygon components'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'inside'
      and validation.confirmed_territory = 'sabah'
      and validation.boundary_dataset_id =
        '33000000-0000-0000-0000-000000000002'
    from public.validate_east_malaysia_site(
      5::double precision,
      5::double precision,
      3::smallint
    ) as validation
  ),
  'point inside the synthetic Sabah polygon must validate inside Sabah'
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'inside'
      and validation.confirmed_territory = 'sarawak'
    from public.validate_east_malaysia_site(
      5::double precision,
      25::double precision,
      5::smallint
    ) as validation
  ),
  'point inside the synthetic Sarawak polygon must validate inside Sarawak'
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'inside'
      and validation.confirmed_territory = 'labuan'
    from public.validate_east_malaysia_site(
      1::double precision,
      41::double precision,
      10::smallint
    ) as validation
  ),
  'point inside the first synthetic Labuan component must validate inside Labuan'
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'inside'
      and validation.confirmed_territory = 'labuan'
    from public.validate_east_malaysia_site(
      1::double precision,
      45::double precision,
      3::smallint
    ) as validation
  ),
  'point inside the second synthetic Labuan component must validate inside Labuan'
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'inside'
      and validation.confirmed_territory = 'sabah'
    from public.validate_east_malaysia_site(
      5::double precision,
      0::double precision,
      3::smallint
    ) as validation
  ),
  'ST_Covers must treat a point exactly on a synthetic boundary as inside'
);

select pg_temp.assert_true(
  (
    select validation.validation_status = 'outside'
      and validation.confirmed_territory is null
      and validation.boundary_dataset_id =
        '33000000-0000-0000-0000-000000000002'
    from public.validate_east_malaysia_site(
      20::double precision,
      60::double precision,
      5::smallint
    ) as validation
  ),
  'point outside every synthetic polygon must validate outside without territory'
);

reset role;

-- Temporarily overlap two synthetic territory polygons. The active dataset is
-- still structurally complete, but a point matching both must be rejected.
update public.east_malaysia_territory_boundaries
set boundary = gis.st_geomfromtext(
  'MULTIPOLYGON(((5 5,15 5,15 15,5 15,5 5)))',
  4326
)::gis.geometry(MultiPolygon, 4326)
where id = '34000000-0000-0000-0000-000000000002';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

do $$
begin
  perform *
  from public.validate_east_malaysia_site(
    7::double precision,
    7::double precision,
    3::smallint
  );
  raise exception 'Expected overlapping boundary ambiguity to fail';
exception
  when sqlstate '22000' then null;
end;
$$;

reset role;

update public.east_malaysia_territory_boundaries
set boundary = gis.st_geomfromtext(
  'MULTIPOLYGON(((20 0,30 0,30 10,20 10,20 0)))',
  4326
)::gis.geometry(MultiPolygon, 4326)
where id = '34000000-0000-0000-0000-000000000002';

-- Invalid coordinates and radius values must be rejected before any boundary
-- result can be returned.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

do $$
begin
  perform * from public.validate_east_malaysia_site(
    91::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected latitude above 90 to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    (-91)::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected latitude below -90 to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    181::double precision,
    3::smallint
  );
  raise exception 'Expected longitude above 180 to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    (-181)::double precision,
    3::smallint
  );
  raise exception 'Expected longitude below -180 to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    'NaN'::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected NaN latitude to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    'Infinity'::double precision,
    3::smallint
  );
  raise exception 'Expected infinite longitude to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    '-Infinity'::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected infinite latitude to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    4::smallint
  );
  raise exception 'Expected unsupported radius to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    0::smallint
  );
  raise exception 'Expected zero radius to fail';
exception
  when sqlstate '22023' then null;
end;
$$;

reset role;

-- A profile without authoritative membership cannot use the validator.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000301',
  true
);

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected no-company validator call to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- A syntactically valid JWT subject without any authoritative profile is also
-- denied without revealing whether other membership data exists.
select pg_temp.assert_true(
  not exists (
    select 1
    from public.profiles as profile
    where profile.user_id = '32000000-0000-0000-0000-000000000999'
  ),
  'no-profile validator fixture must not have a profile row'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000999',
  true
);

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected validator call without a profile to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- anon has no EXECUTE privilege. This fails before validator internals run.
set local role anon;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $$
begin
  perform * from public.validate_east_malaysia_site(
    5::double precision,
    5::double precision,
    3::smallint
  );
  raise exception 'Expected unauthenticated validator call to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- Boundary tables are owner-maintained only, even though service_role can call
-- the validator. Test direct modification denial for every API-facing role.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

do $$
begin
  update public.east_malaysia_boundary_datasets
  set attribution = 'Authenticated forged attribution'
  where id = '33000000-0000-0000-0000-000000000002';
  raise exception 'Expected authenticated boundary update to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;
set local role anon;

do $$
begin
  delete from public.east_malaysia_territory_boundaries;
  raise exception 'Expected anon boundary delete to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;
set local role service_role;

do $$
begin
  insert into public.east_malaysia_boundary_datasets (
    source_provider,
    source_reference,
    source_version,
    licence,
    attribution
  )
  values (
    'Forbidden service provider',
    'https://example.invalid/forbidden-service-import',
    'forbidden-v1',
    'Synthetic',
    'Synthetic'
  );
  raise exception 'Expected service_role boundary insert to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- Existing repository-shaped create remains compatible and receives unverified
-- defaults. Authenticated SELECT includes the new nullable geography column.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

select pg_temp.insert_assessment(
  'Synthetic A1 own assessment',
  '32000000-0000-0000-0000-000000000101'
);

select pg_temp.insert_assessment(
  'Synthetic A1 delete assessment',
  '32000000-0000-0000-0000-000000000101'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
      and pg_catalog.bool_and(
        assessment.geographic_validation_status = 'unverified'
      )
      and pg_catalog.bool_and(assessment.site_location is null)
      and pg_catalog.bool_and(assessment.analysis_radius_km is null)
      and pg_catalog.bool_and(assessment.company_id =
        '31000000-0000-0000-0000-000000000001')
    from public.station_assessments as assessment
    where assessment.location_name = 'Synthetic A1 own assessment'
  ),
  'legacy 14-field create must derive ownership and default to unverified'
);

-- Direct forged INSERT names protected columns and must fail at the ACL layer.
do $$
begin
  insert into public.station_assessments (
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
    explanation,
    site_location,
    analysis_radius_km,
    geographic_validation_status,
    confirmed_territory,
    boundary_dataset_id,
    geographically_validated_at
  )
  values (
    '32000000-0000-0000-0000-000000000101',
    'Synthetic forged geographic insert',
    100,
    3,
    1000,
    2,
    3,
    3,
    3,
    3,
    3,
    50,
    'Synthetic',
    'Synthetic',
    'Synthetic',
    gis.st_setsrid(gis.st_makepoint(5, 5), 4326)::gis.geography,
    3,
    'inside',
    'sabah',
    '33000000-0000-0000-0000-000000000002',
    now()
  );
  raise exception 'Expected forged geographic insert to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  update public.station_assessments
  set
    geographic_validation_status = 'inside',
    confirmed_territory = 'sabah'
  where location_name = 'Synthetic A1 own assessment';
  raise exception 'Expected forged geographic update to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments as assessment
    where assessment.location_name = 'Synthetic A1 own assessment'
      and assessment.site_location is null
  ),
  'authenticated SELECT must return assessment rows containing nullable geography'
);

reset role;

-- Same-company read, creator mutation, admin mutation, and cross-company
-- isolation continue to use the unchanged company-assessment RLS policies.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000102',
  true
);

select pg_temp.insert_assessment(
  'Synthetic A2 teammate assessment',
  '32000000-0000-0000-0000-000000000102'
);

select pg_temp.insert_assessment(
  'Synthetic A2 admin delete assessment',
  '32000000-0000-0000-0000-000000000102'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments as assessment
    where assessment.location_name = 'Synthetic A1 own assessment'
  ),
  'same-company teammate assessment must remain readable'
);

select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Synthetic teammate must not update A1'
      where location_name = 'Synthetic A1 own assessment'
      returning 1
    )
    select count(*) = 0 from changed
  ),
  'normal users must not update another same-company assessment'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000101',
  true
);

select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Synthetic creator update succeeded'
      where location_name = 'Synthetic A1 own assessment'
      returning 1
    )
    select count(*) = 1 from changed
  ),
  'creator update authorization must remain intact'
);

select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'Synthetic A1 delete assessment'
      returning 1
    )
    select count(*) = 1 from removed
  ),
  'creator delete authorization must remain intact'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000103',
  true
);

select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Synthetic admin update succeeded'
      where location_name = 'Synthetic A2 teammate assessment'
      returning 1
    )
    select count(*) = 1 from changed
  ),
  'company-admin teammate update authorization must remain intact'
);

select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'Synthetic A2 admin delete assessment'
      returning 1
    )
    select count(*) = 1 from removed
  ),
  'company-admin teammate delete authorization must remain intact'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000201',
  true
);

select pg_temp.insert_assessment(
  'Synthetic B protected assessment',
  '32000000-0000-0000-0000-000000000201'
);

select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.station_assessments as assessment
    where assessment.location_name = 'Synthetic A1 own assessment'
  ),
  'cross-company assessment reads must remain isolated'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000103',
  true
);

select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Synthetic cross-company admin attempt'
      where location_name = 'Synthetic B protected assessment'
      returning 1
    )
    select count(*) = 0 from changed
  ),
  'company admin must not update a cross-company assessment'
);

select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'Synthetic B protected assessment'
      returning 1
    )
    select count(*) = 0 from removed
  ),
  'company admin must not delete a cross-company assessment'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '32000000-0000-0000-0000-000000000301',
  true
);

select pg_temp.assert_true(
  (select count(*) = 0 from public.station_assessments),
  'no-company assessment read denial must remain intact'
);

reset role;

-- Reconfirm original rows, including IDs, ownership, scoring, status, and
-- timestamps, are byte-for-byte unchanged by this transactional test.
select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_geography_original_assessments as original
    left join public.station_assessments as assessment
      on assessment.id = original.id
    where assessment.id is null
      or pg_catalog.to_jsonb(assessment) is distinct from original.row_data
  ),
  'original assessment IDs, ownership, scoring, geography, and timestamps must remain unchanged'
);

select pg_temp.assert_true(
  (
    select count(*)
    from public.station_assessments as assessment
    join pg_temp.module2_geography_original_assessments as original
      on original.id = assessment.id
  ) = (
    select count(*)
    from pg_temp.module2_geography_original_assessments
  ),
  'every original assessment row must remain present'
);

rollback;
