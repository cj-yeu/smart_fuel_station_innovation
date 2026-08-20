-- Module 2 server-authorized validated assessment creation tests.
-- Run only in an isolated Supabase/PostgreSQL verification environment after
-- applying all Module 2 migrations through the validated-create migration.

begin;

-- Some SQL Editor sessions materialize the real session temp namespace only
-- after the first temporary object is created.
create temporary table module2_validated_create_test_session_init (
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
as $module2_validated_create_assert$
begin
  if condition is distinct from true then
    raise exception 'Module 2 validated-create assertion failed: %', message;
  end if;
end;
$module2_validated_create_assert$;

create temporary table module2_validated_create_original_assessments
on commit drop
as
select
  assessment.id,
  pg_catalog.to_jsonb(assessment) as row_data
from public.station_assessments as assessment;

create temporary table module2_validated_create_test_points (
  territory text primary key,
  point gis.geometry(Point, 4326) not null,
  dataset_id uuid not null,
  location_name text not null,
  population_density numeric not null,
  traffic_level integer not null,
  registered_vehicle_count integer not null,
  nearby_fuel_stations integer not null,
  competitor_distance_km numeric not null,
  road_accessibility integer not null,
  commercial_activity integer not null,
  residential_activity integer not null,
  land_accessibility integer not null,
  final_score numeric not null,
  suitability_category text not null,
  recommendation text not null,
  explanation text not null,
  analysis_radius_km smallint not null
)
on commit drop;

insert into pg_temp.module2_validated_create_test_points (
  territory,
  point,
  dataset_id,
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
  analysis_radius_km
)
select
  expected.territory,
  gis.st_pointonsurface(boundary_entry.boundary)::gis.geometry(Point, 4326),
  dataset.id,
  expected.location_name,
  expected.population_density,
  expected.traffic_level,
  expected.registered_vehicle_count,
  expected.nearby_fuel_stations,
  expected.competitor_distance_km,
  expected.road_accessibility,
  expected.commercial_activity,
  expected.residential_activity,
  expected.land_accessibility,
  expected.final_score,
  expected.suitability_category,
  expected.recommendation,
  expected.explanation,
  expected.analysis_radius_km
from public.east_malaysia_boundary_datasets as dataset
join public.east_malaysia_territory_boundaries as boundary_entry
  on boundary_entry.dataset_id = dataset.id
join (
  values
    (
      'sabah', 'Validated sabah site', 1234.5::numeric, 4, 25000, 2,
      4.25::numeric, 5, 4, 3, 2, 72.3::numeric, 'Good',
      'Test recommendation', 'Test explanation', 3::smallint
    ),
    (
      'sarawak', 'Validated sarawak site', 2345.6::numeric, 5, 35000, 3,
      5.5::numeric, 4, 5, 4, 3, 82.4::numeric, 'Very Good',
      'Sarawak recommendation', 'Sarawak explanation', 5::smallint
    ),
    (
      'labuan', 'Validated labuan site', 3456.7::numeric, 2, 15000, 1,
      6.75::numeric, 3, 2, 5, 4, 64.8::numeric, 'Moderate',
      'Labuan recommendation', 'Labuan explanation', 10::smallint
    )
) as expected(
  territory,
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
  analysis_radius_km
)
  on expected.territory = boundary_entry.territory
where dataset.is_active;

insert into pg_temp.module2_validated_create_test_points (
  territory,
  point,
  dataset_id,
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
  analysis_radius_km
)
select
  'outside',
  gis.st_setsrid(
    gis.st_makepoint(
      gis.st_xmin(dataset_extent.extent) - 1,
      gis.st_ymin(dataset_extent.extent) - 1
    ),
    4326
  )::gis.geometry(Point, 4326),
  dataset_extent.dataset_id,
  'Rejected outside site',
  1234.5,
  4,
  25000,
  2,
  4.25,
  5,
  4,
  3,
  2,
  72.3,
  'Good',
  'Test recommendation',
  'Test explanation',
  3
from (
  select
    dataset.id as dataset_id,
    gis.st_extent(boundary_entry.boundary) as extent
  from public.east_malaysia_boundary_datasets as dataset
  join public.east_malaysia_territory_boundaries as boundary_entry
    on boundary_entry.dataset_id = dataset.id
  where dataset.is_active
  group by dataset.id
) as dataset_extent;

create temporary table module2_validated_create_created_ids (
  territory text primary key,
  assessment_id uuid not null unique
)
on commit drop;

-- This security-invoker helper only shortens repeated calls. The authenticated
-- caller still executes the real SECURITY DEFINER RPC and its full checks.
create function pg_temp.create_validated_assessment(
  p_point gis.geometry,
  p_dataset_id uuid,
  p_location_name text,
  p_population_density numeric,
  p_traffic_level integer,
  p_registered_vehicle_count integer,
  p_nearby_fuel_stations integer,
  p_competitor_distance_km numeric,
  p_road_accessibility integer,
  p_commercial_activity integer,
  p_residential_activity integer,
  p_land_accessibility integer,
  p_final_score numeric,
  p_suitability_category text,
  p_recommendation text,
  p_explanation text,
  p_radius smallint,
  p_request_id uuid
)
returns uuid
language sql
set search_path = ''
as $module2_validated_create_test_call$
  select public.create_validated_station_assessment(
    p_location_name,
    p_population_density,
    p_traffic_level,
    p_registered_vehicle_count,
    p_nearby_fuel_stations,
    p_competitor_distance_km,
    p_road_accessibility,
    p_commercial_activity,
    p_residential_activity,
    p_land_accessibility,
    p_final_score,
    p_suitability_category,
    p_recommendation,
    p_explanation,
    gis.st_y(p_point),
    gis.st_x(p_point),
    p_radius,
    p_dataset_id,
    p_request_id
  )
$module2_validated_create_test_call$;

do $module2_validated_create_temp_grants$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception
      'Module 2 validated-create temporary schema was not initialized';
  end if;

  execute pg_catalog.format(
    'grant usage on schema %I to authenticated, anon',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant execute on function %I.assert_true(boolean, text) to authenticated, anon',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant execute on function %I.create_validated_assessment(gis.geometry, uuid, text, numeric, integer, integer, integer, numeric, integer, integer, integer, integer, numeric, text, text, text, smallint, uuid) to authenticated',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant select on table %I.module2_validated_create_test_points to authenticated',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant select, insert on table %I.module2_validated_create_created_ids to authenticated',
    v_temp_schema
  );
end;
$module2_validated_create_temp_grants$;

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 4
    from pg_temp.module2_validated_create_test_points
  ),
  'test inputs must contain Sabah, Sarawak, Labuan, and outside points'
);

select pg_temp.assert_true(
  pg_catalog.to_regprocedure(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'
  ) is not null,
  'validated assessment create RPC must exist with the exact expected signature'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_validated_create_test_points as test_point
    where test_point.territory in ('sabah', 'sarawak', 'labuan')
      and (
        gis.st_isempty(test_point.point)
        or gis.st_srid(test_point.point) <> 4326
        or gis.st_geometrytype(test_point.point) <> 'ST_Point'
        or not exists (
          select 1
          from public.east_malaysia_boundary_datasets as dataset
          where dataset.id = test_point.dataset_id
            and dataset.is_active
        )
        or (
          select pg_catalog.count(*)
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id = test_point.dataset_id
            and gis.st_covers(boundary_entry.boundary, test_point.point)
        ) <> 1
        or (
          select pg_catalog.min(boundary_entry.territory)
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id = test_point.dataset_id
            and gis.st_covers(boundary_entry.boundary, test_point.point)
        ) is distinct from test_point.territory
        or not exists (
          select 1
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id = test_point.dataset_id
            and boundary_entry.territory = test_point.territory
            and gis.st_contains(boundary_entry.boundary, test_point.point)
        )
      )
  ),
  'derived interior points must be valid and independently covered by exactly their expected active-dataset territory'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_validated_create_test_points as test_point
    where test_point.territory = 'outside'
      and (
        gis.st_isempty(test_point.point)
        or gis.st_srid(test_point.point) <> 4326
        or gis.st_geometrytype(test_point.point) <> 'ST_Point'
        or gis.st_x(test_point.point) not between -180 and 180
        or gis.st_y(test_point.point) not between -90 and 90
        or not exists (
          select 1
          from public.east_malaysia_boundary_datasets as dataset
          where dataset.id = test_point.dataset_id
            and dataset.is_active
        )
        or exists (
          select 1
          from public.east_malaysia_territory_boundaries as boundary_entry
          where boundary_entry.dataset_id = test_point.dataset_id
            and gis.st_covers(boundary_entry.boundary, test_point.point)
        )
      )
  ),
  'derived outside point must be valid, in input range, and independently uncovered by the active dataset'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    cross join lateral unnest(procedure_entry.proargnames) as argument_name
    where procedure_entry.oid =
      'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'::regprocedure
      and argument_name in (
        'user_id',
        'company_id',
        'confirmed_territory',
        'geographic_validation_status',
        'geographically_validated_at',
        'p_user_id',
        'p_company_id',
        'p_confirmed_territory',
        'p_geographic_validation_status',
        'p_geographically_validated_at'
      )
  ),
  'RPC signature must not expose ownership or authoritative geography parameters'
);

insert into public.fuel_companies (
  id,
  company_code,
  company_name
)
values
  (
    '51000000-0000-0000-0000-000000000001',
    'MODULE2_VALIDATED_CREATE_A',
    'Module 2 Validated Create Company One'
  ),
  (
    '51000000-0000-0000-0000-000000000002',
    'MODULE2_VALIDATED_CREATE_B',
    'Module 2 Validated Create Company Two'
  );

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '52000000-0000-0000-0000-000000000001',
    'module2-validated-creator@example.invalid',
    '{"full_name":"Module 2 Validated Creator"}'::jsonb
  ),
  (
    '52000000-0000-0000-0000-000000000002',
    'module2-validated-teammate@example.invalid',
    '{"full_name":"Module 2 Validated Teammate"}'::jsonb
  ),
  (
    '52000000-0000-0000-0000-000000000003',
    'module2-validated-cross-company@example.invalid',
    '{"full_name":"Module 2 Validated Cross Company"}'::jsonb
  ),
  (
    '52000000-0000-0000-0000-000000000004',
    'module2-validated-no-company@example.invalid',
    '{"full_name":"Module 2 Validated No Company"}'::jsonb
  );

update public.profiles
set company_id = '51000000-0000-0000-0000-000000000001',
    role = 'company_user'
where user_id in (
  '52000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000002'
);

update public.profiles
set company_id = '51000000-0000-0000-0000-000000000002',
    role = 'company_user'
where user_id = '52000000-0000-0000-0000-000000000003';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000001',
  true
);

do $module2_validated_create_inside_cases$
declare
  v_case record;
  v_assessment_id uuid;
begin
  for v_case in
    select test_point.*
    from pg_temp.module2_validated_create_test_points as test_point
    where test_point.territory in ('sabah', 'sarawak', 'labuan')
    order by test_point.territory
  loop
    select pg_temp.create_validated_assessment(
      v_case.point,
      v_case.dataset_id,
      v_case.location_name,
      v_case.population_density,
      v_case.traffic_level,
      v_case.registered_vehicle_count,
      v_case.nearby_fuel_stations,
      v_case.competitor_distance_km,
      v_case.road_accessibility,
      v_case.commercial_activity,
      v_case.residential_activity,
      v_case.land_accessibility,
      v_case.final_score,
      v_case.suitability_category,
      v_case.recommendation,
      v_case.explanation,
      v_case.analysis_radius_km,
      case v_case.territory
        when 'labuan' then '71000000-0000-0000-0000-000000000001'::uuid
        when 'sabah' then '71000000-0000-0000-0000-000000000002'::uuid
        when 'sarawak' then '71000000-0000-0000-0000-000000000003'::uuid
      end
    )
    into strict v_assessment_id;

    insert into pg_temp.module2_validated_create_created_ids (
      territory,
      assessment_id
    )
    values (v_case.territory, v_assessment_id);
  end loop;
end;
$module2_validated_create_inside_cases$;

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(
        assessment.user_id =
          '52000000-0000-0000-0000-000000000001'
      )
      and pg_catalog.bool_and(
        assessment.company_id =
          '51000000-0000-0000-0000-000000000001'
      )
      and pg_catalog.bool_and(assessment.location_name = 'Validated sabah site')
      and pg_catalog.bool_and(assessment.population_density = 1234.5)
      and pg_catalog.bool_and(assessment.traffic_level = 4)
      and pg_catalog.bool_and(assessment.registered_vehicle_count = 25000)
      and pg_catalog.bool_and(assessment.nearby_fuel_stations = 2)
      and pg_catalog.bool_and(assessment.competitor_distance_km = 4.25)
      and pg_catalog.bool_and(assessment.road_accessibility = 5)
      and pg_catalog.bool_and(assessment.commercial_activity = 4)
      and pg_catalog.bool_and(assessment.residential_activity = 3)
      and pg_catalog.bool_and(assessment.land_accessibility = 2)
      and pg_catalog.bool_and(assessment.final_score = 72.3)
      and pg_catalog.bool_and(assessment.suitability_category = 'Good')
      and pg_catalog.bool_and(assessment.recommendation = 'Test recommendation')
      and pg_catalog.bool_and(assessment.explanation = 'Test explanation')
      and pg_catalog.bool_and(assessment.analysis_radius_km = 3)
      and pg_catalog.bool_and(
        assessment.geographic_validation_status = 'inside'
      )
      and pg_catalog.bool_and(assessment.confirmed_territory = 'sabah')
      and pg_catalog.bool_and(
        assessment.boundary_dataset_id = test_point.dataset_id
      )
      and pg_catalog.bool_and(
        assessment.geographically_validated_at = pg_catalog.now()
      )
      and pg_catalog.bool_and(
        gis.st_x(assessment.site_location::gis.geometry) =
          gis.st_x(test_point.point)
      )
      and pg_catalog.bool_and(
        gis.st_y(assessment.site_location::gis.geometry) =
          gis.st_y(test_point.point)
      )
    from pg_temp.module2_validated_create_created_ids as created
    join public.station_assessments as assessment
      on assessment.id = created.assessment_id
    join pg_temp.module2_validated_create_test_points as test_point
      on test_point.territory = created.territory
    where created.territory = 'sabah'
  ),
  'Sabah create must persist exact content and authoritative ownership/geography'
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 3
      and pg_catalog.count(distinct assessment.id) = 3
      and pg_catalog.bool_and(assessment.id = created.assessment_id)
      and pg_catalog.bool_and(
        assessment.user_id = '52000000-0000-0000-0000-000000000001'
      )
      and pg_catalog.bool_and(
        assessment.company_id = '51000000-0000-0000-0000-000000000001'
      )
      and pg_catalog.bool_and(
        assessment.location_name = expected.location_name
      )
      and pg_catalog.bool_and(
        assessment.population_density = expected.population_density
      )
      and pg_catalog.bool_and(
        assessment.traffic_level = expected.traffic_level
      )
      and pg_catalog.bool_and(
        assessment.registered_vehicle_count =
          expected.registered_vehicle_count
      )
      and pg_catalog.bool_and(
        assessment.nearby_fuel_stations = expected.nearby_fuel_stations
      )
      and pg_catalog.bool_and(
        assessment.competitor_distance_km = expected.competitor_distance_km
      )
      and pg_catalog.bool_and(
        assessment.road_accessibility = expected.road_accessibility
      )
      and pg_catalog.bool_and(
        assessment.commercial_activity = expected.commercial_activity
      )
      and pg_catalog.bool_and(
        assessment.residential_activity = expected.residential_activity
      )
      and pg_catalog.bool_and(
        assessment.land_accessibility = expected.land_accessibility
      )
      and pg_catalog.bool_and(assessment.final_score = expected.final_score)
      and pg_catalog.bool_and(
        assessment.suitability_category = expected.suitability_category
      )
      and pg_catalog.bool_and(
        assessment.recommendation = expected.recommendation
      )
      and pg_catalog.bool_and(assessment.explanation = expected.explanation)
      and pg_catalog.bool_and(
        not gis.st_isempty(assessment.site_location::gis.geometry)
      )
      and pg_catalog.bool_and(
        gis.st_geometrytype(assessment.site_location::gis.geometry) = 'ST_Point'
      )
      and pg_catalog.bool_and(
        gis.st_srid(assessment.site_location::gis.geometry) = 4326
      )
      and pg_catalog.bool_and(
        gis.st_x(assessment.site_location::gis.geometry) =
          gis.st_x(expected.point)
      )
      and pg_catalog.bool_and(
        gis.st_y(assessment.site_location::gis.geometry) =
          gis.st_y(expected.point)
      )
      and pg_catalog.bool_and(
        assessment.confirmed_territory = created.territory
      )
      and pg_catalog.bool_and(
        assessment.analysis_radius_km = expected.analysis_radius_km
      )
      and pg_catalog.bool_and(
        assessment.geographic_validation_status = 'inside'
      )
      and pg_catalog.bool_and(
        assessment.boundary_dataset_id = expected.dataset_id
      )
      and pg_catalog.bool_and(
        assessment.geographically_validated_at is not null
      )
      and pg_catalog.bool_and(assessment.created_at is not null)
      and pg_catalog.bool_and(assessment.updated_at is not null)
      and pg_catalog.bool_and(
        assessment.geographically_validated_at = assessment.created_at
      )
      and pg_catalog.bool_and(assessment.updated_at = assessment.created_at)
      and pg_catalog.bool_and(assessment.created_at = pg_catalog.now())
    from pg_temp.module2_validated_create_created_ids as created
    join public.station_assessments as assessment
      on assessment.id = created.assessment_id
    join pg_temp.module2_validated_create_test_points as expected
      on expected.territory = created.territory
  ),
  'Sabah, Sarawak, and Labuan calls must each persist one complete authoritative row matching the returned UUID'
);

do $module2_validated_create_outside_rejection$
declare
  v_before bigint;
  v_point record;
begin
  select pg_catalog.count(*) into v_before
  from public.station_assessments;

  select test_point.* into strict v_point
  from pg_temp.module2_validated_create_test_points as test_point
  where test_point.territory = 'outside';

  begin
    perform pg_temp.create_validated_assessment(
      v_point.point,
      v_point.dataset_id,
      v_point.location_name,
      v_point.population_density,
      v_point.traffic_level,
      v_point.registered_vehicle_count,
      v_point.nearby_fuel_stations,
      v_point.competitor_distance_km,
      v_point.road_accessibility,
      v_point.commercial_activity,
      v_point.residential_activity,
      v_point.land_accessibility,
      v_point.final_score,
      v_point.suitability_category,
      v_point.recommendation,
      v_point.explanation,
      v_point.analysis_radius_km,
      '71000000-0000-0000-0000-000000000004'::uuid
    );
    raise exception 'Expected outside validated create to fail';
  exception
    when sqlstate '22023' then null;
  end;

  perform pg_temp.assert_true(
    (select pg_catalog.count(*) from public.station_assessments) = v_before,
    'outside rejection must not create an assessment'
  );
end;
$module2_validated_create_outside_rejection$;

do $module2_validated_create_stale_dataset$
declare
  v_before bigint;
  v_point record;
begin
  select pg_catalog.count(*) into v_before
  from public.station_assessments;

  select test_point.* into strict v_point
  from pg_temp.module2_validated_create_test_points as test_point
  where test_point.territory = 'sabah';

  begin
    perform pg_temp.create_validated_assessment(
      v_point.point,
      '59000000-0000-0000-0000-000000000099',
      'Rejected stale site',
      v_point.population_density,
      v_point.traffic_level,
      v_point.registered_vehicle_count,
      v_point.nearby_fuel_stations,
      v_point.competitor_distance_km,
      v_point.road_accessibility,
      v_point.commercial_activity,
      v_point.residential_activity,
      v_point.land_accessibility,
      v_point.final_score,
      v_point.suitability_category,
      v_point.recommendation,
      v_point.explanation,
      v_point.analysis_radius_km,
      '71000000-0000-0000-0000-000000000005'::uuid
    );
    raise exception 'Expected stale dataset validated create to fail';
  exception
    when sqlstate '40001' then null;
  end;

  perform pg_temp.assert_true(
    (select pg_catalog.count(*) from public.station_assessments) = v_before,
    'stale dataset rejection must not create an assessment'
  );
end;
$module2_validated_create_stale_dataset$;

do $module2_validated_create_invalid_inputs$
declare
  v_case record;
  v_dataset_id uuid;
begin
  select test_point.dataset_id into strict v_dataset_id
  from pg_temp.module2_validated_create_test_points as test_point
  where test_point.territory = 'sabah';

  for v_case in
    select invalid_case.*
    from (
      values
        ('null latitude', null::double precision, 116::double precision, 3::smallint),
        ('invalid latitude', 91::double precision, 116::double precision, 3::smallint),
        ('invalid longitude', 5::double precision, 181::double precision, 3::smallint),
        ('unsupported radius', 5::double precision, 116::double precision, 4::smallint),
        ('null radius', 5::double precision, 116::double precision, null::smallint)
    ) as invalid_case(case_name, latitude, longitude, radius)
  loop
    begin
      perform public.create_validated_station_assessment(
        p_location_name => 'Rejected invalid input'::text,
        p_population_density => 1234.5::numeric,
        p_traffic_level => 4::integer,
        p_registered_vehicle_count => 25000::integer,
        p_nearby_fuel_stations => 2::integer,
        p_competitor_distance_km => 4.25::numeric,
        p_road_accessibility => 5::integer,
        p_commercial_activity => 4::integer,
        p_residential_activity => 3::integer,
        p_land_accessibility => 2::integer,
        p_final_score => 72.3::numeric,
        p_suitability_category => 'Good'::text,
        p_recommendation => 'Recommendation'::text,
        p_explanation => 'Explanation'::text,
        p_latitude => v_case.latitude::double precision,
        p_longitude => v_case.longitude::double precision,
        p_analysis_radius_km => v_case.radius::smallint,
        p_expected_boundary_dataset_id => v_dataset_id::uuid,
        p_request_id => '71000000-0000-0000-0000-000000000006'::uuid
      );
      raise exception 'Expected % to fail', v_case.case_name;
    exception
      when sqlstate '22023' then null;
    end;
  end loop;

  perform pg_temp.assert_true(
    not exists (
      select 1
      from public.station_assessments as assessment
      where assessment.location_name = 'Rejected invalid input'
    ),
    'invalid parameter rejection must not create an assessment'
  );
end;
$module2_validated_create_invalid_inputs$;

-- Direct clients still cannot write authoritative geography or ownership.
do $module2_validated_create_direct_insert_denied$
declare
  v_point record;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_create_test_points as test_point
  where test_point.territory = 'sabah';

  begin
    insert into public.station_assessments (
      user_id, location_name, population_density, traffic_level,
      registered_vehicle_count, nearby_fuel_stations, competitor_distance_km,
      road_accessibility, commercial_activity, residential_activity,
      land_accessibility, final_score, suitability_category, recommendation,
      explanation, site_location, geographic_validation_status
    ) values (
      '52000000-0000-0000-0000-000000000001', 'Forbidden direct geography',
      1, 3, 1, 0, 1, 3, 3, 3, 3, 50, 'Moderate', 'No', 'No',
      v_point.point::gis.geography, 'inside'
    );
    raise exception 'Expected direct geography insert to fail';
  exception
    when sqlstate '42501' then null;
  end;
end;
$module2_validated_create_direct_insert_denied$;

select pg_temp.assert_true(
  not exists (
    select 1
    from public.station_assessments as assessment
    where assessment.location_name = 'Forbidden direct geography'
  ),
  'protected geography INSERT denial must leave no assessment row'
);

do $module2_validated_create_direct_update_denied$
declare
  v_id uuid;
  v_before jsonb;
begin
  select created.assessment_id into strict v_id
  from pg_temp.module2_validated_create_created_ids as created
  where created.territory = 'sabah';

  select pg_catalog.to_jsonb(assessment)
  into strict v_before
  from public.station_assessments as assessment
  where assessment.id = v_id;

  begin
    update public.station_assessments
    set geographic_validation_status = 'unverified'
    where id = v_id;
    raise exception 'Expected direct geography update to fail';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    update public.station_assessments
    set company_id = '51000000-0000-0000-0000-000000000002'
    where id = v_id;
    raise exception 'Expected direct ownership update to fail';
  exception
    when sqlstate '42501' then null;
  end;

  perform pg_temp.assert_true(
    (
      select pg_catalog.to_jsonb(assessment) is not distinct from v_before
      from public.station_assessments as assessment
      where assessment.id = v_id
    ),
    'protected UPDATE denials must preserve the complete assessment row'
  );
end;
$module2_validated_create_direct_update_denied$;

-- Legacy repository-shaped direct creation remains supported.
do $module2_validated_create_legacy_insert$
declare
  v_id uuid;
begin
  insert into public.station_assessments (
    user_id, location_name, population_density, traffic_level,
    registered_vehicle_count, nearby_fuel_stations, competitor_distance_km,
    road_accessibility, commercial_activity, residential_activity,
    land_accessibility, final_score, suitability_category, recommendation,
    explanation
  ) values (
    '52000000-0000-0000-0000-000000000001', 'Legacy compatible create',
    10, 3, 100, 1, 2, 3, 3, 3, 3, 50, 'Moderate', 'Legacy', 'Legacy'
  )
  returning id into v_id;

  perform pg_temp.assert_true(
    exists (
      select 1
      from public.station_assessments as assessment
      where assessment.id = v_id
        and assessment.user_id =
          '52000000-0000-0000-0000-000000000001'
        and assessment.company_id =
          '51000000-0000-0000-0000-000000000001'
        and assessment.geographic_validation_status = 'unverified'
        and assessment.site_location is null
        and assessment.boundary_dataset_id is null
    ),
    'legacy repository-shaped create must remain compatible'
  );
end;
$module2_validated_create_legacy_insert$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000002',
  true
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 4
    from public.station_assessments as assessment
    where assessment.user_id =
      '52000000-0000-0000-0000-000000000001'
  ),
  'same-company teammate must see validated and legacy creator rows'
);

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000003',
  true
);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.station_assessments as assessment
    where assessment.user_id =
      '52000000-0000-0000-0000-000000000001'
  ),
  'cross-company caller must not see validated assessments'
);

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000004',
  true
);

do $module2_validated_create_no_company$
begin
  perform public.create_validated_station_assessment(
    p_location_name => 'No company'::text,
    p_population_density => 1::numeric,
    p_traffic_level => 3::integer,
    p_registered_vehicle_count => 1::integer,
    p_nearby_fuel_stations => 0::integer,
    p_competitor_distance_km => 1::numeric,
    p_road_accessibility => 3::integer,
    p_commercial_activity => 3::integer,
    p_residential_activity => 3::integer,
    p_land_accessibility => 3::integer,
    p_final_score => 50::numeric,
    p_suitability_category => 'Moderate'::text,
    p_recommendation => 'No'::text,
    p_explanation => 'No'::text,
    p_latitude => 5::double precision,
    p_longitude => 116::double precision,
    p_analysis_radius_km => 3::smallint,
    p_expected_boundary_dataset_id =>
      '59000000-0000-0000-0000-000000000001'::uuid,
    p_request_id => '71000000-0000-0000-0000-000000000007'::uuid
  );
  raise exception 'Expected no-company caller to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_validated_create_no_company$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000999',
  true
);

do $module2_validated_create_missing_profile$
begin
  perform public.create_validated_station_assessment(
    p_location_name => 'Missing profile'::text,
    p_population_density => 1::numeric,
    p_traffic_level => 3::integer,
    p_registered_vehicle_count => 1::integer,
    p_nearby_fuel_stations => 0::integer,
    p_competitor_distance_km => 1::numeric,
    p_road_accessibility => 3::integer,
    p_commercial_activity => 3::integer,
    p_residential_activity => 3::integer,
    p_land_accessibility => 3::integer,
    p_final_score => 50::numeric,
    p_suitability_category => 'Moderate'::text,
    p_recommendation => 'No'::text,
    p_explanation => 'No'::text,
    p_latitude => 5::double precision,
    p_longitude => 116::double precision,
    p_analysis_radius_km => 3::smallint,
    p_expected_boundary_dataset_id =>
      '59000000-0000-0000-0000-000000000001'::uuid,
    p_request_id => '71000000-0000-0000-0000-000000000008'::uuid
  );
  raise exception 'Expected missing-profile caller to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_validated_create_missing_profile$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $module2_validated_create_anon$
begin
  perform public.create_validated_station_assessment(
    p_location_name => 'Anonymous'::text,
    p_population_density => 1::numeric,
    p_traffic_level => 3::integer,
    p_registered_vehicle_count => 1::integer,
    p_nearby_fuel_stations => 0::integer,
    p_competitor_distance_km => 1::numeric,
    p_road_accessibility => 3::integer,
    p_commercial_activity => 3::integer,
    p_residential_activity => 3::integer,
    p_land_accessibility => 3::integer,
    p_final_score => 50::numeric,
    p_suitability_category => 'Moderate'::text,
    p_recommendation => 'No'::text,
    p_explanation => 'No'::text,
    p_latitude => 5::double precision,
    p_longitude => 116::double precision,
    p_analysis_radius_km => 3::smallint,
    p_expected_boundary_dataset_id =>
      '59000000-0000-0000-0000-000000000001'::uuid,
    p_request_id => '71000000-0000-0000-0000-000000000009'::uuid
  );
  raise exception 'Expected anonymous caller to fail';
exception
  when sqlstate '42501' then null;
end;
$module2_validated_create_anon$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.station_assessments as assessment
    where assessment.location_name in (
      'No company',
      'Missing profile',
      'Anonymous'
    )
  ),
  'authorization denials must not create assessments'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_validated_create_original_assessments as original
    left join public.station_assessments as assessment
      on assessment.id = original.id
    where assessment.id is null
      or pg_catalog.to_jsonb(assessment) is distinct from original.row_data
  ),
  'every pre-existing assessment and timestamp must remain unchanged'
);

rollback;
