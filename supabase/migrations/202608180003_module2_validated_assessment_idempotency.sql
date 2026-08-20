-- Add server-enforced idempotency to validated assessment creation.
-- Existing rows remain unchanged with a NULL request identifier.

do $module2_validated_idempotency_preconditions$
begin
  if exists (
    select 1
    from pg_catalog.pg_roles as migration_role_entry
    where migration_role_entry.rolname = current_user
      and migration_role_entry.rolname in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception 'Module 2 idempotency migration must run as a non-API owner role';
  end if;

  if pg_catalog.to_regclass('public.station_assessments') is null
    or pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.east_malaysia_boundary_datasets') is null
    or pg_catalog.to_regclass('public.east_malaysia_territory_boundaries') is null then
    raise exception 'Module 2 idempotency migration requires deployed foundation tables';
  end if;

  if pg_catalog.to_regprocedure(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid)'
  ) is null then
    raise exception 'Module 2 idempotency migration requires the original validated-create RPC';
  end if;

  if pg_catalog.to_regprocedure(
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'
  ) is not null
    or exists (
      select 1
      from pg_catalog.pg_attribute as attribute_entry
      where attribute_entry.attrelid = 'public.station_assessments'::regclass
        and attribute_entry.attname = 'validated_create_request_id'
        and attribute_entry.attnum > 0
        and not attribute_entry.attisdropped
    )
    or pg_catalog.to_regclass(
      'public.station_assessments_validated_create_request_uidx'
    ) is not null then
    raise exception 'Module 2 idempotency target objects already exist';
  end if;

  if exists (
    select 1
    from public.profiles as profile
    group by profile.user_id
    having pg_catalog.count(*) > 1
  ) or exists (
    select 1
    from public.station_assessments as assessment
    where assessment.company_id is null
  ) then
    raise exception 'Module 2 idempotency migration requires authoritative ownership';
  end if;
end;
$module2_validated_idempotency_preconditions$;

create temporary table module2_validated_idempotency_pre_state
on commit drop
as
select
  coalesce(
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(assessment)
        order by assessment.id
      )
      from public.station_assessments as assessment
    ),
    '[]'::jsonb
  ) as assessment_rows,
  coalesce(
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(policy_entry)
        order by policy_entry.policyname
      )
      from pg_catalog.pg_policies as policy_entry
      where policy_entry.schemaname = 'public'
        and policy_entry.tablename = 'station_assessments'
    ),
    '[]'::jsonb
  ) as assessment_policies,
  coalesce(
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.pg_get_triggerdef(trigger_entry.oid, true)
        order by trigger_entry.tgname
      )
      from pg_catalog.pg_trigger as trigger_entry
      where trigger_entry.tgrelid = 'public.station_assessments'::regclass
        and not trigger_entry.tgisinternal
    ),
    '[]'::jsonb
  ) as assessment_triggers,
  (
    select pg_catalog.jsonb_build_object(
      'owner', relation_entry.relowner,
      'acl', relation_entry.relacl,
      'rls_enabled', relation_entry.relrowsecurity,
      'rls_forced', relation_entry.relforcerowsecurity
    )
    from pg_catalog.pg_class as relation_entry
    where relation_entry.oid = 'public.station_assessments'::regclass
  ) as assessment_table_security,
  coalesce(
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', attribute_entry.attname,
          'acl', attribute_entry.attacl
        )
        order by attribute_entry.attnum
      )
      from pg_catalog.pg_attribute as attribute_entry
      where attribute_entry.attrelid = 'public.station_assessments'::regclass
        and attribute_entry.attnum > 0
        and not attribute_entry.attisdropped
    ),
    '[]'::jsonb
  ) as assessment_column_acls;

alter table public.station_assessments
add column validated_create_request_id uuid null;

comment on column public.station_assessments.validated_create_request_id is
  'Server-protected idempotency key for one authenticated creator validated-create request. NULL for legacy/manual rows.';

-- The nullable, defaultless column keeps the existing 14-field manual insert
-- contract compatible while excluding this server-only value from its ACL.

create unique index station_assessments_validated_create_request_uidx
on public.station_assessments (user_id, validated_create_request_id)
where validated_create_request_id is not null;

revoke insert (validated_create_request_id),
  update (validated_create_request_id)
on public.station_assessments
from public, anon, authenticated, service_role;

drop function public.create_validated_station_assessment(
  text, numeric, integer, integer, integer, numeric, integer, integer,
  integer, integer, numeric, text, text, text, double precision,
  double precision, smallint, uuid
);

create function public.create_validated_station_assessment(
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
  p_latitude double precision,
  p_longitude double precision,
  p_analysis_radius_km smallint,
  p_expected_boundary_dataset_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $module2_validated_idempotent_create_function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_locked_dataset_id uuid;
  v_boundary_id uuid;
  v_locked_boundary_count integer := 0;
  v_validation record;
  v_existing public.station_assessments%rowtype;
  v_assessment_id uuid;
  v_point gis.geography(Point, 4326);
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
    raise exception 'An authoritative company membership is required'
      using errcode = '42501';
  end if;

  if p_request_id is null then
    raise exception 'A validated-create request ID is required'
      using errcode = '22023';
  end if;

  if p_location_name is null
    or p_population_density is null
    or p_population_density < 0
    or p_population_density::text in ('NaN', 'Infinity', '-Infinity')
    or p_traffic_level is null
    or p_traffic_level not between 1 and 5
    or p_registered_vehicle_count is null
    or p_registered_vehicle_count < 0
    or p_nearby_fuel_stations is null
    or p_nearby_fuel_stations < 0
    or p_competitor_distance_km is null
    or p_competitor_distance_km < 0
    or p_competitor_distance_km::text in ('NaN', 'Infinity', '-Infinity')
    or p_road_accessibility is null
    or p_road_accessibility not between 1 and 5
    or p_commercial_activity is null
    or p_commercial_activity not between 1 and 5
    or p_residential_activity is null
    or p_residential_activity not between 1 and 5
    or p_land_accessibility is null
    or p_land_accessibility not between 1 and 5
    or p_final_score is null
    or p_final_score < 0
    or p_final_score > 100
    or p_final_score::text in ('NaN', 'Infinity', '-Infinity')
    or p_suitability_category is null
    or p_recommendation is null
    or p_explanation is null then
    raise exception 'Assessment content parameters are invalid'
      using errcode = '22023';
  end if;

  if p_latitude is null
    or p_latitude = 'NaN'::double precision
    or p_latitude < -90
    or p_latitude > 90
    or p_longitude is null
    or p_longitude = 'NaN'::double precision
    or p_longitude < -180
    or p_longitude > 180
    or p_analysis_radius_km is null
    or p_analysis_radius_km not in (3, 5, 10)
    or p_expected_boundary_dataset_id is null then
    raise exception 'Validated site parameters are invalid'
      using errcode = '22023';
  end if;

  v_point := gis.st_setsrid(
    gis.st_makepoint(p_longitude, p_latitude),
    4326
  )::gis.geography(Point, 4326);

  -- Transaction-scoped serialization makes the following lookup authoritative
  -- after an earlier identical request commits. Hash collisions only serialize
  -- unrelated requests; the unique index remains the final correctness guard.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  select assessment.*
  into v_existing
  from public.station_assessments as assessment
  where assessment.user_id = v_user_id
    and assessment.validated_create_request_id = p_request_id
  for update;

  if found then
    if v_existing.company_id is distinct from v_company_id
      or v_existing.location_name is distinct from p_location_name
      or v_existing.population_density is distinct from p_population_density
      or v_existing.traffic_level is distinct from p_traffic_level
      or v_existing.registered_vehicle_count is distinct from p_registered_vehicle_count
      or v_existing.nearby_fuel_stations is distinct from p_nearby_fuel_stations
      or v_existing.competitor_distance_km is distinct from p_competitor_distance_km
      or v_existing.road_accessibility is distinct from p_road_accessibility
      or v_existing.commercial_activity is distinct from p_commercial_activity
      or v_existing.residential_activity is distinct from p_residential_activity
      or v_existing.land_accessibility is distinct from p_land_accessibility
      or v_existing.final_score is distinct from p_final_score
      or v_existing.suitability_category is distinct from p_suitability_category
      or v_existing.recommendation is distinct from p_recommendation
      or v_existing.explanation is distinct from p_explanation
      or v_existing.site_location is null
      or gis.st_x(v_existing.site_location::gis.geometry) is distinct from p_longitude
      or gis.st_y(v_existing.site_location::gis.geometry) is distinct from p_latitude
      or v_existing.analysis_radius_km is distinct from p_analysis_radius_km
      or v_existing.geographic_validation_status is distinct from 'inside'
      or v_existing.confirmed_territory is null
      or v_existing.boundary_dataset_id is distinct from p_expected_boundary_dataset_id then
      raise exception 'Validated-create request ID was reused with different input'
        using errcode = '22023';
    end if;
    return v_existing.id;
  end if;

  select dataset.id
  into v_locked_dataset_id
  from public.east_malaysia_boundary_datasets as dataset
  where dataset.is_active
  for share;

  if not found or v_locked_dataset_id <> p_expected_boundary_dataset_id then
    raise exception 'The boundary validation is stale; retry validation'
      using errcode = '40001';
  end if;

  for v_boundary_id in
    select boundary_entry.id
    from public.east_malaysia_territory_boundaries as boundary_entry
    where boundary_entry.dataset_id = v_locked_dataset_id
    order by boundary_entry.id
    for share
  loop
    v_locked_boundary_count := v_locked_boundary_count + 1;
  end loop;

  if v_locked_boundary_count <> 3 then
    raise exception 'The boundary validation is stale; retry validation'
      using errcode = '40001';
  end if;

  select validation.*
  into strict v_validation
  from public.validate_east_malaysia_site(
    p_latitude,
    p_longitude,
    p_analysis_radius_km
  ) as validation;

  if v_validation.boundary_dataset_id is distinct from v_locked_dataset_id then
    raise exception 'The boundary validation is stale; retry validation'
      using errcode = '40001';
  end if;

  if v_validation.validation_status is distinct from 'inside'
    or v_validation.confirmed_territory is null then
    raise exception 'The site is not confirmed inside East Malaysia'
      using errcode = '22023';
  end if;

  insert into public.station_assessments (
    user_id, company_id, location_name, population_density, traffic_level,
    registered_vehicle_count, nearby_fuel_stations, competitor_distance_km,
    road_accessibility, commercial_activity, residential_activity,
    land_accessibility, final_score, suitability_category, recommendation,
    explanation, site_location, analysis_radius_km,
    geographic_validation_status, confirmed_territory, boundary_dataset_id,
    geographically_validated_at, validated_create_request_id
  ) values (
    v_user_id, v_company_id, p_location_name, p_population_density,
    p_traffic_level, p_registered_vehicle_count, p_nearby_fuel_stations,
    p_competitor_distance_km, p_road_accessibility, p_commercial_activity,
    p_residential_activity, p_land_accessibility, p_final_score,
    p_suitability_category, p_recommendation, p_explanation, v_point,
    p_analysis_radius_km, 'inside', v_validation.confirmed_territory,
    v_locked_dataset_id, pg_catalog.now(), p_request_id
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$module2_validated_idempotent_create_function$;

revoke all privileges
on function public.create_validated_station_assessment(
  text, numeric, integer, integer, integer, numeric, integer, integer,
  integer, integer, numeric, text, text, text, double precision,
  double precision, smallint, uuid, uuid
)
from public, anon, authenticated, service_role;

grant execute
on function public.create_validated_station_assessment(
  text, numeric, integer, integer, integer, numeric, integer, integer,
  integer, integer, numeric, text, text, text, double precision,
  double precision, smallint, uuid, uuid
)
to authenticated;

comment on function public.create_validated_station_assessment(
  text, numeric, integer, integer, integer, numeric, integer, integer,
  integer, integer, numeric, text, text, text, double precision,
  double precision, smallint, uuid, uuid
) is
  'Creates or returns one server-validated assessment for auth.uid() and a caller-generated logical request UUID. The obsolete non-idempotent overload is removed.';

do $module2_validated_idempotency_postconditions$
declare
  v_function regprocedure :=
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid,uuid)'::regprocedure;
begin
  if exists (
    select 1
    from pg_temp.module2_validated_idempotency_pre_state as before_state
    where before_state.assessment_rows is distinct from (
      select coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(assessment) - 'validated_create_request_id'
          order by assessment.id
        ),
        '[]'::jsonb
      )
      from public.station_assessments as assessment
    )
      or before_state.assessment_policies is distinct from (
        select coalesce(
          pg_catalog.jsonb_agg(
            pg_catalog.to_jsonb(policy_entry)
            order by policy_entry.policyname
          ),
          '[]'::jsonb
        )
        from pg_catalog.pg_policies as policy_entry
        where policy_entry.schemaname = 'public'
          and policy_entry.tablename = 'station_assessments'
      )
      or before_state.assessment_triggers is distinct from (
        select coalesce(
          pg_catalog.jsonb_agg(
            pg_catalog.pg_get_triggerdef(trigger_entry.oid, true)
            order by trigger_entry.tgname
          ),
          '[]'::jsonb
        )
        from pg_catalog.pg_trigger as trigger_entry
        where trigger_entry.tgrelid = 'public.station_assessments'::regclass
          and not trigger_entry.tgisinternal
      )
      or before_state.assessment_table_security is distinct from (
        select pg_catalog.jsonb_build_object(
          'owner', relation_entry.relowner,
          'acl', relation_entry.relacl,
          'rls_enabled', relation_entry.relrowsecurity,
          'rls_forced', relation_entry.relforcerowsecurity
        )
        from pg_catalog.pg_class as relation_entry
        where relation_entry.oid = 'public.station_assessments'::regclass
      )
      or before_state.assessment_column_acls is distinct from (
        select coalesce(
          pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'name', attribute_entry.attname,
              'acl', attribute_entry.attacl
            )
            order by attribute_entry.attnum
          ),
          '[]'::jsonb
        )
        from pg_catalog.pg_attribute as attribute_entry
        where attribute_entry.attrelid = 'public.station_assessments'::regclass
          and attribute_entry.attnum > 0
          and not attribute_entry.attisdropped
          and attribute_entry.attname <> 'validated_create_request_id'
      )
  ) then
    raise exception 'Module 2 idempotency migration changed existing rows or security metadata';
  end if;

  if exists (
    select 1
    from public.station_assessments as assessment
    where assessment.validated_create_request_id is not null
  ) or not exists (
    select 1
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attname = 'validated_create_request_id'
      and attribute_entry.atttypid = 'uuid'::regtype
      and not attribute_entry.attnotnull
      and not attribute_entry.atthasdef
      and not attribute_entry.attisdropped
  ) then
    raise exception 'Module 2 idempotency column did not preserve legacy rows';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_entry
    where index_entry.indexrelid =
      pg_catalog.to_regclass(
        'public.station_assessments_validated_create_request_uidx'
      )
      and index_entry.indrelid = 'public.station_assessments'::regclass
      and index_entry.indisunique
      and index_entry.indisvalid
      and index_entry.indisready
      and index_entry.indnkeyatts = 2
      and index_entry.indnatts = 2
      and pg_catalog.pg_get_indexdef(index_entry.indexrelid, 1, true) = 'user_id'
      and pg_catalog.pg_get_indexdef(index_entry.indexrelid, 2, true) =
        'validated_create_request_id'
      and pg_catalog.pg_get_expr(
        index_entry.indpred,
        index_entry.indrelid
      ) in (
        '(validated_create_request_id IS NOT NULL)',
        'validated_create_request_id IS NOT NULL'
      )
  )
    or pg_catalog.to_regprocedure(
      'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid)'
    ) is not null
    or (
      select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure_entry
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure_entry.pronamespace
      where namespace.nspname = 'public'
        and procedure_entry.proname = 'create_validated_station_assessment'
    ) <> 1 then
    raise exception 'Module 2 idempotency RPC identity is ambiguous or incomplete';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure_entry.proowner
    where procedure_entry.oid = v_function
      and owner_role.rolname = current_user
      and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
      and procedure_entry.prosecdef
      and procedure_entry.proconfig = array['search_path=""']::text[]
  ) or pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
    or pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE')
    or exists (
      select 1
      from pg_catalog.pg_proc as procedure_entry
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          procedure_entry.proacl,
          pg_catalog.acldefault('f', procedure_entry.proowner)
        )
      ) as function_acl
      where procedure_entry.oid = v_function
        and function_acl.grantee = 0
        and function_acl.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Module 2 idempotency RPC security metadata is invalid';
  end if;

  if pg_catalog.has_column_privilege(
    'authenticated', 'public.station_assessments',
    'validated_create_request_id', 'INSERT'
  ) or pg_catalog.has_column_privilege(
    'authenticated', 'public.station_assessments',
    'validated_create_request_id', 'UPDATE'
  ) then
    raise exception 'Module 2 idempotency request column is client-writable';
  end if;
end;
$module2_validated_idempotency_postconditions$;

drop table pg_temp.module2_validated_idempotency_pre_state;
