-- Module 2 geoBoundaries MYS ADM1 seed tests.
--
-- Run only in an isolated Supabase/PostgreSQL verification environment after
-- applying the geography foundation and boundary-seed migrations. All users,
-- profiles, and companies created here are synthetic and rolled back.

begin;

-- Materialize the real session temp namespace before creating pg_temp helpers.
create temporary table module2_boundary_seed_test_session_init (
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
as $module2_boundary_seed_assert$
begin
  if condition is distinct from true then
    raise exception 'Module 2 boundary seed assertion failed: %', message;
  end if;
end;
$module2_boundary_seed_assert$;

-- Preserve complete pre-test assessment rows. Neither the seed migration nor
-- this test is permitted to change any assessment value or timestamp.
create temporary table module2_boundary_seed_original_assessments
on commit drop
as
select
  assessment.id,
  pg_catalog.to_jsonb(assessment) as row_data
from public.station_assessments as assessment;

-- Derive validator inputs from the installed full-resolution geometries. The
-- outside point is one degree below and west of the complete dataset extent,
-- then independently proved to be outside every polygon and away from edges.
create temporary table module2_boundary_seed_test_points (
  territory text primary key,
  point gis.geometry(Point, 4326) not null
)
on commit drop;

insert into pg_temp.module2_boundary_seed_test_points (
  territory,
  point
)
select
  boundary_entry.territory,
  gis.st_pointonsurface(boundary_entry.boundary)::gis.geometry(Point, 4326)
from public.east_malaysia_territory_boundaries as boundary_entry
where boundary_entry.dataset_id =
  'de8b4433-7315-5e60-8195-1d76744765eb'
union all
select
  'outside',
  gis.st_setsrid(
    gis.st_makepoint(
      gis.st_xmin(dataset_extent.extent) - 1,
      gis.st_ymin(dataset_extent.extent) - 1
    ),
    4326
  )::gis.geometry(Point, 4326)
from (
  select gis.st_extent(boundary_entry.boundary) as extent
  from public.east_malaysia_territory_boundaries as boundary_entry
  where boundary_entry.dataset_id =
    'de8b4433-7315-5e60-8195-1d76744765eb'
) as dataset_extent;

-- Resolve the actual numbered temp schema. pg_temp is a session alias and is
-- not a reliable static GRANT target in every SQL Editor session.
do $module2_boundary_seed_temp_grants$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception
      'Module 2 boundary seed test temporary schema was not initialized';
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
    'grant select on table %I.module2_boundary_seed_test_points to authenticated',
    v_temp_schema
  );
end;
$module2_boundary_seed_temp_grants$;

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(dataset.is_active)
      and pg_catalog.bool_and(
        dataset.source_provider = 'geoBoundaries MYS ADM1'
      )
      and pg_catalog.bool_and(
        dataset.source_reference = 'https://www.geoboundaries.org/'
      )
      and pg_catalog.bool_and(
        dataset.source_version =
          'MYS ADM1 source SHA-256 de8b44337315de60019951d76744765ebdd5efc9c5823e0933b4dc15a0ed20d4'
      )
      and pg_catalog.bool_and(dataset.source_release_date is null)
      and pg_catalog.bool_and(dataset.licence like '%CC BY 4.0%')
      and pg_catalog.bool_and(
        dataset.licence like '%creativecommons.org/licenses/by/4.0/%'
      )
    from public.east_malaysia_boundary_datasets as dataset
    where dataset.id = 'de8b4433-7315-5e60-8195-1d76744765eb'
  ),
  'expected deterministic geoBoundaries dataset must exist once and be active'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
    from public.east_malaysia_boundary_datasets as dataset
    where dataset.is_active
  ),
  'exactly one complete active boundary dataset must exist'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 3
      and pg_catalog.count(distinct boundary_entry.territory) = 3
      and pg_catalog.bool_and(
        boundary_entry.territory in ('sabah', 'sarawak', 'labuan')
      )
    from public.east_malaysia_territory_boundaries as boundary_entry
    where boundary_entry.dataset_id =
      'de8b4433-7315-5e60-8195-1d76744765eb'
  ),
  'active dataset must contain exactly Sabah, Sarawak, and Labuan'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.east_malaysia_territory_boundaries as boundary_entry
    where boundary_entry.dataset_id =
      'de8b4433-7315-5e60-8195-1d76744765eb'
      and (
        boundary_entry.boundary is null
        or gis.st_isempty(boundary_entry.boundary)
        or not gis.st_isvalid(boundary_entry.boundary)
        or gis.st_ndims(boundary_entry.boundary) <> 2
        or gis.st_srid(boundary_entry.boundary) <> 4326
        or gis.st_geometrytype(boundary_entry.boundary) <> 'ST_MultiPolygon'
      )
  ),
  'every seeded geometry must be valid non-empty 2D SRID 4326 MultiPolygon'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.east_malaysia_territory_boundaries as first_boundary
    join public.east_malaysia_territory_boundaries as second_boundary
      on first_boundary.territory < second_boundary.territory
      and first_boundary.dataset_id = second_boundary.dataset_id
    where first_boundary.dataset_id =
      'de8b4433-7315-5e60-8195-1d76744765eb'
      and gis.st_relate(
        first_boundary.boundary,
        second_boundary.boundary,
        '2********'
      )
  ),
  'seeded territories must not overlap by area'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 3
      and pg_catalog.bool_and(
        gis.st_contains(boundary_entry.boundary, test_point.point)
      )
    from pg_temp.module2_boundary_seed_test_points as test_point
    join public.east_malaysia_territory_boundaries as boundary_entry
      on boundary_entry.territory = test_point.territory
      and boundary_entry.dataset_id =
        'de8b4433-7315-5e60-8195-1d76744765eb'
    where test_point.territory in ('sabah', 'sarawak', 'labuan')
  ),
  'ST_PointOnSurface must derive one strict interior point per territory'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(
        gis.st_x(test_point.point) between -180 and 180
      )
      and pg_catalog.bool_and(
        gis.st_y(test_point.point) between -90 and 90
      )
      and pg_catalog.bool_and(
        not exists (
          select 1
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id =
            'de8b4433-7315-5e60-8195-1d76744765eb'
            and gis.st_covers(boundary_entry.boundary, test_point.point)
        )
      )
      and pg_catalog.bool_and(
        (
          select pg_catalog.min(
            gis.st_distance(boundary_entry.boundary, test_point.point)
          )
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id =
            'de8b4433-7315-5e60-8195-1d76744765eb'
        ) > 0.5
      )
    from pg_temp.module2_boundary_seed_test_points as test_point
    where test_point.territory = 'outside'
  ),
  'derived outside point must be unambiguous and away from every boundary'
);

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
      from pg_catalog.pg_policy as policy_entry
      where policy_entry.polrelid in (
        'public.east_malaysia_boundary_datasets'::regclass,
        'public.east_malaysia_territory_boundaries'::regclass
      )
    ),
  'boundary tables must retain RLS with zero API policies'
);

do $module2_boundary_seed_acl$
declare
  v_check record;
  v_has_privilege boolean;
begin
  for v_check in
    select
      checked_role.role_name,
      boundary_table.table_name,
      checked_privilege.privilege_name
    from (values ('PUBLIC'), ('anon'), ('authenticated'), ('service_role'))
      as checked_role(role_name)
    cross join (
      values
        ('public.east_malaysia_boundary_datasets'),
        ('public.east_malaysia_territory_boundaries')
    ) as boundary_table(table_name)
    cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'))
      as checked_privilege(privilege_name)
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
        ) as table_acl
        where relation.oid = pg_catalog.to_regclass(v_check.table_name)
          and table_acl.grantee = 0
          and table_acl.privilege_type = v_check.privilege_name
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
$module2_boundary_seed_acl$;

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
    )
    and not exists (
      select 1
      from pg_catalog.pg_proc as procedure_entry
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          procedure_entry.proacl,
          pg_catalog.acldefault('f', procedure_entry.proowner)
        )
      ) as function_acl
      where procedure_entry.oid =
        'public.validate_east_malaysia_site(double precision,double precision,smallint)'::regprocedure
        and function_acl.grantee = 0
        and function_acl.privilege_type = 'EXECUTE'
    ),
  'validator EXECUTE must remain limited to authenticated and service_role'
);

-- Rollback-only synthetic identities. auth.users inserts invoke the existing
-- profile trigger; only the member receives authoritative company membership.
insert into public.fuel_companies (
  id,
  company_code,
  company_name
)
values (
  '41000000-0000-0000-0000-000000000001',
  'MODULE2_BOUNDARY_SEED_TEST',
  'Module 2 Boundary Seed Test Company'
);

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values
  (
    '42000000-0000-0000-0000-000000000001',
    'module2-boundary-member@example.invalid',
    '{"full_name":"Module 2 Boundary Member"}'::jsonb
  ),
  (
    '42000000-0000-0000-0000-000000000002',
    'module2-boundary-no-company@example.invalid',
    '{"full_name":"Module 2 Boundary No Company"}'::jsonb
  );

update public.profiles
set
  company_id = '41000000-0000-0000-0000-000000000001',
  role = 'company_user'
where user_id = '42000000-0000-0000-0000-000000000001';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '42000000-0000-0000-0000-000000000001',
  true
);

do $module2_boundary_seed_inside_validation$
declare
  v_point record;
  v_validation record;
begin
  for v_point in
    select test_point.territory, test_point.point
    from pg_temp.module2_boundary_seed_test_points as test_point
    where test_point.territory in ('sabah', 'sarawak', 'labuan')
    order by test_point.territory
  loop
    select validation.*
    into strict v_validation
    from public.validate_east_malaysia_site(
      gis.st_y(v_point.point),
      gis.st_x(v_point.point),
      3::smallint
    ) as validation;

    perform pg_temp.assert_true(
      v_validation.validation_status = 'inside'
        and v_validation.confirmed_territory = v_point.territory
        and v_validation.boundary_dataset_id =
          'de8b4433-7315-5e60-8195-1d76744765eb',
      pg_catalog.format(
        'interior point must validate inside %s with expected dataset UUID',
        v_point.territory
      )
    );
  end loop;
end;
$module2_boundary_seed_inside_validation$;

select pg_temp.assert_true(
  (
    select validation.validation_status = 'outside'
      and validation.confirmed_territory is null
      and validation.boundary_dataset_id =
        'de8b4433-7315-5e60-8195-1d76744765eb'
    from pg_temp.module2_boundary_seed_test_points as test_point
    cross join lateral public.validate_east_malaysia_site(
      gis.st_y(test_point.point),
      gis.st_x(test_point.point),
      10::smallint
    ) as validation
    where test_point.territory = 'outside'
  ),
  'derived point outside all three territories must validate outside'
);

do $module2_boundary_seed_invalid_inputs$
declare
  v_case record;
begin
  for v_case in
    select invalid_case.*
    from (
      values
        ('null latitude', null::double precision, 115::double precision, 3::smallint),
        ('null longitude', 5::double precision, null::double precision, 3::smallint),
        ('latitude above range', 91::double precision, 115::double precision, 3::smallint),
        ('longitude above range', 5::double precision, 181::double precision, 3::smallint),
        ('NaN latitude', 'NaN'::double precision, 115::double precision, 3::smallint),
        ('infinite longitude', 5::double precision, 'Infinity'::double precision, 3::smallint),
        ('unsupported radius', 5::double precision, 115::double precision, 4::smallint),
        ('zero radius', 5::double precision, 115::double precision, 0::smallint)
    ) as invalid_case(case_name, latitude, longitude, radius)
  loop
    begin
      perform *
      from public.validate_east_malaysia_site(
        v_case.latitude,
        v_case.longitude,
        v_case.radius
      );
      raise exception 'Expected % to fail', v_case.case_name;
    exception
      when sqlstate '22023' then null;
    end;
  end loop;
end;
$module2_boundary_seed_invalid_inputs$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '42000000-0000-0000-0000-000000000002',
  true
);

do $module2_boundary_seed_no_company$
begin
  perform *
  from public.validate_east_malaysia_site(
    5::double precision,
    115::double precision,
    3::smallint
  );
  raise exception 'Expected no-company validator call to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_boundary_seed_no_company$;

reset role;

select pg_temp.assert_true(
  not exists (
    select 1
    from public.profiles as profile
    where profile.user_id = '42000000-0000-0000-0000-000000000999'
  ),
  'missing-profile fixture must not have an authoritative profile'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '42000000-0000-0000-0000-000000000999',
  true
);

do $module2_boundary_seed_missing_profile$
begin
  perform *
  from public.validate_east_malaysia_site(
    5::double precision,
    115::double precision,
    3::smallint
  );
  raise exception 'Expected missing-profile validator call to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_boundary_seed_missing_profile$;

reset role;
set local role anon;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $module2_boundary_seed_anon$
begin
  perform *
  from public.validate_east_malaysia_site(
    5::double precision,
    115::double precision,
    3::smallint
  );
  raise exception 'Expected anonymous validator call to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_boundary_seed_anon$;

reset role;

select pg_temp.assert_true(
  (
    select pg_catalog.count(*)
    from pg_temp.module2_boundary_seed_original_assessments
  ) = (
    select pg_catalog.count(*)
    from public.station_assessments
  )
    and not exists (
      select 1
      from pg_temp.module2_boundary_seed_original_assessments as original
      full join public.station_assessments as assessment
        on assessment.id = original.id
      where original.id is null
        or assessment.id is null
        or pg_catalog.to_jsonb(assessment) is distinct from original.row_data
    ),
  'assessment IDs, values, ownership, scoring, geography, and timestamps must remain unchanged'
);

rollback;
