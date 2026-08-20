-- Transactional runtime matrix for validated-create idempotency.
begin;

create temporary table module2_validated_idempotency_test_session_init (
  initialized boolean not null default true
) on commit drop;

create function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
set search_path = ''
as $module2_validated_idempotency_assert$
begin
  if condition is distinct from true then
    raise exception 'Module 2 validated idempotency assertion failed: %', message;
  end if;
end;
$module2_validated_idempotency_assert$;

create temporary table module2_validated_idempotency_original_assessments
on commit drop
as
select
  assessment.id,
  pg_catalog.to_jsonb(assessment) - 'validated_create_request_id' as row_data
from public.station_assessments as assessment;

create temporary table module2_validated_idempotency_points
on commit drop
as
select
  boundary_entry.territory,
  dataset.id as dataset_id,
  gis.st_pointonsurface(boundary_entry.boundary) as point
from public.east_malaysia_boundary_datasets as dataset
join public.east_malaysia_territory_boundaries as boundary_entry
  on boundary_entry.dataset_id = dataset.id
where dataset.is_active
  and boundary_entry.territory in ('sabah', 'sarawak', 'labuan');

create function pg_temp.create_validated_assessment(
  p_point gis.geometry,
  p_dataset_id uuid,
  p_location_name text,
  p_request_id uuid
)
returns uuid
language sql
set search_path = ''
as $module2_validated_idempotency_call$
  select public.create_validated_station_assessment(
    p_location_name => p_location_name,
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
    p_latitude => gis.st_y(p_point),
    p_longitude => gis.st_x(p_point),
    p_analysis_radius_km => 5::smallint,
    p_expected_boundary_dataset_id => p_dataset_id,
    p_request_id => p_request_id
  )
$module2_validated_idempotency_call$;

do $module2_validated_idempotency_temp_grants$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception 'Module 2 idempotency temporary schema was not initialized';
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
    'grant execute on function %I.create_validated_assessment(gis.geometry, uuid, text, uuid) to authenticated, anon',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant select on table %I.module2_validated_idempotency_points to authenticated, anon',
    v_temp_schema
  );
end;
$module2_validated_idempotency_temp_grants$;

select pg_temp.assert_true(
  pg_catalog.to_regprocedure(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'
  ) is not null,
  'the exact idempotent RPC identity must exist'
);

select pg_temp.assert_true(
  pg_catalog.to_regprocedure(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid)'
  ) is null,
  'the obsolete non-idempotent RPC identity must be absent'
);

select pg_temp.assert_true(
  (select pg_catalog.count(*) from pg_temp.module2_validated_idempotency_points) = 3,
  'the active dataset must provide Sabah, Sarawak, and Labuan test points'
);

select pg_temp.assert_true(
  pg_catalog.pg_get_functiondef(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'::regprocedure
  ) like '%pg_advisory_xact_lock%'
    and pg_catalog.to_regclass(
      'public.station_assessments_validated_create_request_uidx'
    ) is not null,
  'advisory serialization and the unique database guard must both exist'
);

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'anon', 'public.station_assessments',
    'validated_create_request_id', 'INSERT'
  )
    and not pg_catalog.has_column_privilege(
      'anon', 'public.station_assessments',
      'validated_create_request_id', 'UPDATE'
    ),
  'anon must not directly INSERT or UPDATE validated create request IDs'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_catalog.pg_class as relation_entry
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation_entry.relacl,
        pg_catalog.acldefault('r', relation_entry.relowner)
      )
    ) as table_acl
    where relation_entry.oid = 'public.station_assessments'::regclass
      and table_acl.grantee = 0
      and table_acl.privilege_type in ('INSERT', 'UPDATE')
  )
    and not exists (
      select 1
      from pg_catalog.pg_attribute as attribute_entry
      cross join lateral pg_catalog.aclexplode(
        attribute_entry.attacl
      ) as column_acl
      where attribute_entry.attrelid =
        'public.station_assessments'::regclass
        and attribute_entry.attname = 'validated_create_request_id'
        and attribute_entry.attnum > 0
        and not attribute_entry.attisdropped
        and attribute_entry.attacl is not null
        and column_acl.grantee = 0
        and column_acl.privilege_type in ('INSERT', 'UPDATE')
    ),
  'PUBLIC must not directly INSERT or UPDATE validated create request IDs'
);

insert into public.fuel_companies (id, company_code, company_name)
values
  (
    '61000000-0000-0000-0000-000000000001',
    'MODULE2_IDEMPOTENCY_A',
    'Module 2 Idempotency Company One'
  ),
  (
    '61000000-0000-0000-0000-000000000002',
    'MODULE2_IDEMPOTENCY_B',
    'Module 2 Idempotency Company Two'
  );

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '62000000-0000-0000-0000-000000000001',
    'module2-idempotent-creator@example.invalid',
    '{}'::jsonb
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    'module2-idempotent-other@example.invalid',
    '{}'::jsonb
  ),
  (
    '62000000-0000-0000-0000-000000000003',
    'module2-idempotent-no-company@example.invalid',
    '{}'::jsonb
  );

update public.profiles
set company_id = '61000000-0000-0000-0000-000000000001',
    role = 'company_user'
where user_id = '62000000-0000-0000-0000-000000000001';

update public.profiles
set company_id = '61000000-0000-0000-0000-000000000002',
    role = 'company_user'
where user_id = '62000000-0000-0000-0000-000000000002';

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '62000000-0000-0000-0000-000000000001',
  true
);

do $module2_validated_idempotency_first_and_retry$
declare
  v_point record;
  v_first_id uuid;
  v_retry_id uuid;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';

  select pg_temp.create_validated_assessment(
    v_point.point,
    v_point.dataset_id,
    'Idempotent Sabah',
    '63000000-0000-0000-0000-000000000001'
  ) into strict v_first_id;

  select pg_temp.create_validated_assessment(
    v_point.point,
    v_point.dataset_id,
    'Idempotent Sabah',
    '63000000-0000-0000-0000-000000000001'
  ) into strict v_retry_id;

  perform pg_temp.assert_true(
    v_first_id = v_retry_id,
    'an identical sequential retry must return the first assessment UUID'
  );
  perform pg_temp.assert_true(
    (
      select pg_catalog.count(*)
      from public.station_assessments as assessment
      where assessment.user_id = '62000000-0000-0000-0000-000000000001'
        and assessment.validated_create_request_id =
          '63000000-0000-0000-0000-000000000001'
    ) = 1,
    'an identical sequential retry must persist exactly one row'
  );
end;
$module2_validated_idempotency_first_and_retry$;

-- A rollback-only SQL file has one backend session, so it cannot create a true
-- overlapping transaction without an unapproved extension or second client.
-- This repeats the same request in one statement; the migration checks above
-- independently require both the transaction advisory lock and unique index
-- that serialize and guard the corresponding cross-session race.
do $module2_validated_idempotency_same_statement_duplicates$
declare
  v_point record;
  v_distinct_ids bigint;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sarawak';

  select pg_catalog.count(distinct request_result.assessment_id)
  into v_distinct_ids
  from (
    select pg_temp.create_validated_assessment(
      v_point.point,
      v_point.dataset_id,
      'Idempotent Sarawak',
      '63000000-0000-0000-0000-000000000002'
    ) as assessment_id
    from pg_catalog.generate_series(1, 2)
  ) as request_result;

  perform pg_temp.assert_true(
    v_distinct_ids = 1
      and (
        select pg_catalog.count(*)
        from public.station_assessments as assessment
        where assessment.user_id = '62000000-0000-0000-0000-000000000001'
          and assessment.validated_create_request_id =
            '63000000-0000-0000-0000-000000000002'
      ) = 1,
    'duplicate requests in one statement must return one UUID and create one row'
  );
end;
$module2_validated_idempotency_same_statement_duplicates$;

do $module2_validated_idempotency_changed_payload$
declare
  v_point record;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';

  begin
    perform pg_temp.create_validated_assessment(
      v_point.point,
      v_point.dataset_id,
      'Changed Sabah payload',
      '63000000-0000-0000-0000-000000000001'
    );
    raise exception 'Expected changed payload reuse to fail';
  exception
    when sqlstate '22023' then null;
  end;

  perform pg_temp.assert_true(
    (
      select pg_catalog.count(*)
      from public.station_assessments as assessment
      where assessment.user_id = '62000000-0000-0000-0000-000000000001'
        and assessment.validated_create_request_id =
          '63000000-0000-0000-0000-000000000001'
    ) = 1,
    'changed payload reuse must not create or replace an assessment row'
  );
end;
$module2_validated_idempotency_changed_payload$;

do $module2_validated_idempotency_request_acl$
declare
  v_assessment_id uuid;
begin
  select assessment.id into strict v_assessment_id
  from public.station_assessments as assessment
  where assessment.validated_create_request_id =
    '63000000-0000-0000-0000-000000000001';

  begin
    update public.station_assessments
    set validated_create_request_id =
      '63000000-0000-0000-0000-000000000099'
    where id = v_assessment_id;
    raise exception 'Expected direct request ID update to fail';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    insert into public.station_assessments (
      user_id, location_name, population_density, traffic_level,
      registered_vehicle_count, nearby_fuel_stations, competitor_distance_km,
      road_accessibility, commercial_activity, residential_activity,
      land_accessibility, final_score, suitability_category, recommendation,
      explanation, validated_create_request_id
    ) values (
      '62000000-0000-0000-0000-000000000001', 'Forbidden request ID',
      1, 3, 1, 0, 1, 3, 3, 3, 3, 50, 'Moderate', 'No', 'No',
      '63000000-0000-0000-0000-000000000099'
    );
    raise exception 'Expected direct request ID insert to fail';
  exception
    when sqlstate '42501' then null;
  end;
end;
$module2_validated_idempotency_request_acl$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '62000000-0000-0000-0000-000000000002',
  true
);

do $module2_validated_idempotency_other_user$
declare
  v_point record;
  v_other_id uuid;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'labuan';

  select pg_temp.create_validated_assessment(
    v_point.point,
    v_point.dataset_id,
    'Idempotent Labuan Other User',
    '63000000-0000-0000-0000-000000000001'
  ) into strict v_other_id;

  perform pg_temp.assert_true(
    not exists (
      select 1
      from public.station_assessments as assessment
      where assessment.id = v_other_id
        and assessment.user_id <>
          '62000000-0000-0000-0000-000000000002'
    ),
    'another user must never receive or reuse the first creator row'
  );
end;
$module2_validated_idempotency_other_user$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '62000000-0000-0000-0000-000000000001',
  true
);

do $module2_validated_idempotency_denials$
declare
  v_point record;
  v_before bigint;
begin
  select pg_catalog.count(*) into v_before
  from public.station_assessments;

  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';

  begin
    perform pg_temp.create_validated_assessment(
      v_point.point, v_point.dataset_id, 'Missing request ID', null
    );
    raise exception 'Expected missing request ID to fail';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform pg_temp.create_validated_assessment(
      gis.st_setsrid(gis.st_makepoint(0, 0), 4326),
      v_point.dataset_id,
      'Outside idempotent site',
      '63000000-0000-0000-0000-000000000003'
    );
    raise exception 'Expected outside site to fail';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform pg_temp.create_validated_assessment(
      v_point.point,
      '69000000-0000-0000-0000-000000000099',
      'Stale idempotent site',
      '63000000-0000-0000-0000-000000000004'
    );
    raise exception 'Expected stale dataset to fail';
  exception when sqlstate '40001' then null;
  end;

  perform pg_temp.assert_true(
    (select pg_catalog.count(*) from public.station_assessments) = v_before,
    'missing request, outside, and stale denials must create zero rows'
  );
end;
$module2_validated_idempotency_denials$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '62000000-0000-0000-0000-000000000003',
  true
);

do $module2_validated_idempotency_no_company$
declare
  v_point record;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';
  begin
    perform pg_temp.create_validated_assessment(
      v_point.point, v_point.dataset_id, 'No company idempotent',
      '63000000-0000-0000-0000-000000000005'
    );
    raise exception 'Expected no-company caller to fail';
  exception when sqlstate '42501' then null;
  end;
end;
$module2_validated_idempotency_no_company$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '62000000-0000-0000-0000-000000000999',
  true
);

do $module2_validated_idempotency_missing_profile$
declare
  v_point record;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';
  begin
    perform pg_temp.create_validated_assessment(
      v_point.point, v_point.dataset_id, 'Missing profile idempotent',
      '63000000-0000-0000-0000-000000000006'
    );
    raise exception 'Expected missing-profile caller to fail';
  exception when sqlstate '42501' then null;
  end;
end;
$module2_validated_idempotency_missing_profile$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role anon;

do $module2_validated_idempotency_anon$
declare
  v_point record;
begin
  select test_point.* into strict v_point
  from pg_temp.module2_validated_idempotency_points as test_point
  where test_point.territory = 'sabah';
  begin
    perform pg_temp.create_validated_assessment(
      v_point.point, v_point.dataset_id, 'Anonymous idempotent',
      '63000000-0000-0000-0000-000000000007'
    );
    raise exception 'Expected anonymous caller to fail';
  exception when sqlstate '42501' then null;
  end;
end;
$module2_validated_idempotency_anon$;

reset role;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.count(distinct assessment.id) = 2
    from public.station_assessments as assessment
    where assessment.validated_create_request_id =
      '63000000-0000-0000-0000-000000000001'
      and assessment.user_id in (
        '62000000-0000-0000-0000-000000000001',
        '62000000-0000-0000-0000-000000000002'
      )
  ),
  'the same request UUID is isolated per creator and cannot expose another row'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.station_assessments as assessment
    where assessment.location_name in (
      'Missing request ID', 'Outside idempotent site',
      'Stale idempotent site', 'No company idempotent',
      'Missing profile idempotent', 'Anonymous idempotent',
      'Forbidden request ID'
    )
  ),
  'all authorization and validation denials must leave zero rows'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_validated_idempotency_original_assessments as original
    left join public.station_assessments as assessment
      on assessment.id = original.id
    where assessment.id is null
      or pg_catalog.to_jsonb(assessment) - 'validated_create_request_id'
        is distinct from original.row_data
  ),
  'every pre-existing assessment and timestamp must remain unchanged'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_temp.module2_validated_idempotency_original_assessments as original
    join public.station_assessments as assessment
      on assessment.id = original.id
    where assessment.validated_create_request_id is not null
  ),
  'every pre-existing assessment must retain a NULL validated request ID'
);

rollback;
