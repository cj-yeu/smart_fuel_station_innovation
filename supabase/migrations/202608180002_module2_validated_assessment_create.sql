-- Module 2 server-authorized validated assessment persistence.
--
-- The RPC added here revalidates geography and derives ownership inside one
-- PostgreSQL transaction. Clients supply assessment content and an expected
-- boundary dataset UUID, never authoritative ownership or geography results.

do $module2_validated_create_preconditions$
begin
  if exists (
    select 1
    from pg_catalog.pg_roles as migration_role_entry
    where migration_role_entry.rolname = current_user
      and migration_role_entry.rolname in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception
      'Module 2 validated assessment creation requires a non-API migration owner';
  end if;

  if exists (
    select 1
    from (values ('anon'), ('authenticated'), ('service_role'))
      as required_role(role_name)
    where not exists (
      select 1
      from pg_catalog.pg_roles as role_entry
      where role_entry.rolname = required_role.role_name
    )
  ) then
    raise exception
      'Module 2 validated assessment creation requires API roles';
  end if;

  if pg_catalog.to_regclass('public.profiles') is null
    or pg_catalog.to_regclass('public.station_assessments') is null
    or pg_catalog.to_regclass(
      'public.east_malaysia_boundary_datasets'
    ) is null
    or pg_catalog.to_regclass(
      'public.east_malaysia_territory_boundaries'
    ) is null then
    raise exception
      'Module 2 validated assessment creation requires deployed foundation tables';
  end if;

  if exists (
    select 1
    from (
      values
        ('profiles', 'user_id'),
        ('profiles', 'company_id'),
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
        ('station_assessments', 'site_location'),
        ('station_assessments', 'analysis_radius_km'),
        ('station_assessments', 'geographic_validation_status'),
        ('station_assessments', 'confirmed_territory'),
        ('station_assessments', 'boundary_dataset_id'),
        ('station_assessments', 'geographically_validated_at')
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
      'Module 2 validated assessment creation required columns are missing';
  end if;

  if pg_catalog.to_regprocedure(
    'public.validate_east_malaysia_site(double precision,double precision,smallint)'
  ) is null
    or pg_catalog.to_regprocedure(
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
    ) is null then
    raise exception
      'Module 2 validated assessment creation requires geography and ownership functions';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure_entry.pronamespace
    where namespace.nspname = 'public'
      and procedure_entry.proname =
        'create_validated_station_assessment'
  ) then
    raise exception
      'Module 2 validated assessment creation function already exists';
  end if;

  if exists (
    select profile.user_id
    from public.profiles as profile
    group by profile.user_id
    having pg_catalog.count(*) > 1
  ) then
    raise exception
      'Module 2 validated assessment creation requires unique profiles.user_id values';
  end if;

  if (
    select pg_catalog.count(*)
    from public.east_malaysia_boundary_datasets as dataset
    where dataset.is_active
  ) <> 1
    or (
      select pg_catalog.count(*)
      from public.east_malaysia_territory_boundaries as boundary_entry
      join public.east_malaysia_boundary_datasets as dataset
        on dataset.id = boundary_entry.dataset_id
      where dataset.is_active
    ) <> 3 then
    raise exception
      'Module 2 validated assessment creation requires one complete active boundary dataset';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies as policy_entry
    where policy_entry.schemaname = 'public'
      and policy_entry.tablename = 'station_assessments'
  ) <> 4
    or (
      select pg_catalog.count(*)
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
      'Module 2 validated assessment creation requires the company authorization matrix';
  end if;
end;
$module2_validated_create_preconditions$;

-- Snapshot values and authorization catalog state. Creating the RPC must not
-- mutate assessments or weaken any pre-existing RLS, ACL, trigger, or validator.
create temporary table module2_validated_create_foundation_snapshot
on commit drop
as
select
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(assessment)
        order by assessment.id
      ),
      '[]'::jsonb
    )
    from public.station_assessments as assessment
  ) as assessment_rows,
  (
    select pg_catalog.jsonb_build_object(
      'owner', procedure_entry.proowner,
      'security_definer', procedure_entry.prosecdef,
      'config', pg_catalog.to_jsonb(procedure_entry.proconfig),
      'acl', pg_catalog.to_jsonb(procedure_entry.proacl),
      'definition', pg_catalog.pg_get_functiondef(procedure_entry.oid)
    )
    from pg_catalog.pg_proc as procedure_entry
    where procedure_entry.oid =
      'public.validate_east_malaysia_site(double precision,double precision,smallint)'::regprocedure
  ) as validator_state,
  (
    select pg_catalog.jsonb_build_object(
      'owner', relation.relowner,
      'acl', pg_catalog.to_jsonb(relation.relacl),
      'rls', relation.relrowsecurity,
      'force_rls', relation.relforcerowsecurity
    )
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.station_assessments'::regclass
  ) as assessment_relation_state,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', attribute_entry.attname,
          'acl', pg_catalog.to_jsonb(attribute_entry.attacl)
        )
        order by attribute_entry.attnum
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
  ) as assessment_column_acls,
  (
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
  ) as assessment_policies,
  (
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
  ) as assessment_triggers,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', relation.oid::regclass::text,
          'owner', relation.relowner,
          'acl', pg_catalog.to_jsonb(relation.relacl),
          'rls', relation.relrowsecurity,
          'force_rls', relation.relforcerowsecurity
        )
        order by relation.oid::regclass::text
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.east_malaysia_boundary_datasets'::regclass,
      'public.east_malaysia_territory_boundaries'::regclass
    )
  ) as boundary_relation_states,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'table', relation.oid::regclass::text,
          'name', attribute_entry.attname,
          'acl', pg_catalog.to_jsonb(attribute_entry.attacl)
        )
        order by relation.oid::regclass::text, attribute_entry.attnum
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_attribute as attribute_entry
      on attribute_entry.attrelid = relation.oid
    where relation.oid in (
      'public.east_malaysia_boundary_datasets'::regclass,
      'public.east_malaysia_territory_boundaries'::regclass
    )
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
  ) as boundary_column_acls,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', procedure_entry.oid::regprocedure::text,
          'owner', procedure_entry.proowner,
          'security_definer', procedure_entry.prosecdef,
          'config', pg_catalog.to_jsonb(procedure_entry.proconfig),
          'acl', pg_catalog.to_jsonb(procedure_entry.proacl),
          'definition', pg_catalog.pg_get_functiondef(procedure_entry.oid)
        )
        order by procedure_entry.oid::regprocedure::text
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_proc as procedure_entry
    where procedure_entry.oid in (
      'public.current_assessment_company_id()'::regprocedure,
      'public.current_user_is_company_admin()'::regprocedure,
      'public.set_station_assessment_ownership()'::regprocedure,
      'public.prevent_station_assessment_ownership_change()'::regprocedure
    )
  ) as company_function_states,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(policy_entry)
        order by policy_entry.tablename, policy_entry.policyname
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_policies as policy_entry
    where policy_entry.schemaname = 'public'
      and policy_entry.tablename in (
        'east_malaysia_boundary_datasets',
        'east_malaysia_territory_boundaries'
      )
  ) as boundary_policies;

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
  p_expected_boundary_dataset_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $module2_validated_create_function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_locked_dataset_id uuid;
  v_boundary_id uuid;
  v_locked_boundary_count integer := 0;
  v_validation record;
  v_assessment_id uuid;
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

  -- A SHARE lock prevents the active dataset row from being deactivated or
  -- replaced between authoritative validation and assessment insertion.
  select dataset.id
  into v_locked_dataset_id
  from public.east_malaysia_boundary_datasets as dataset
  where dataset.is_active
  for share;

  if not found then
    raise exception 'The boundary validation is stale; retry validation'
      using errcode = '40001';
  end if;

  if v_locked_dataset_id <> p_expected_boundary_dataset_id then
    raise exception 'The boundary validation is stale; retry validation'
      using errcode = '40001';
  end if;

  -- Lock all source rows used by the validator so their geometry cannot change
  -- while the assessment is being constructed.
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
    site_location,
    analysis_radius_km,
    geographic_validation_status,
    confirmed_territory,
    boundary_dataset_id,
    geographically_validated_at
  )
  values (
    v_user_id,
    v_company_id,
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
    gis.st_setsrid(
      gis.st_makepoint(p_longitude, p_latitude),
      4326
    )::gis.geography(Point, 4326),
    p_analysis_radius_km,
    'inside',
    v_validation.confirmed_territory,
    v_locked_dataset_id,
    pg_catalog.now()
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$module2_validated_create_function$;

revoke all privileges
on function public.create_validated_station_assessment(
  text,
  numeric,
  integer,
  integer,
  integer,
  numeric,
  integer,
  integer,
  integer,
  integer,
  numeric,
  text,
  text,
  text,
  double precision,
  double precision,
  smallint,
  uuid
)
from public, anon, authenticated, service_role;

grant execute
on function public.create_validated_station_assessment(
  text,
  numeric,
  integer,
  integer,
  integer,
  numeric,
  integer,
  integer,
  integer,
  integer,
  numeric,
  text,
  text,
  text,
  double precision,
  double precision,
  smallint,
  uuid
)
to authenticated;

comment on function public.create_validated_station_assessment(
  text,
  numeric,
  integer,
  integer,
  integer,
  numeric,
  integer,
  integer,
  integer,
  integer,
  numeric,
  text,
  text,
  text,
  double precision,
  double precision,
  smallint,
  uuid
) is
  'Creates one assessment after same-transaction authoritative East Malaysia validation. Ownership, territory, status, provenance, and validation time are server-derived.';

create temporary table module2_validated_create_foundation_post_state
on commit drop
as
select
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(assessment)
        order by assessment.id
      ),
      '[]'::jsonb
    )
    from public.station_assessments as assessment
  ) as assessment_rows,
  (
    select pg_catalog.jsonb_build_object(
      'owner', procedure_entry.proowner,
      'security_definer', procedure_entry.prosecdef,
      'config', pg_catalog.to_jsonb(procedure_entry.proconfig),
      'acl', pg_catalog.to_jsonb(procedure_entry.proacl),
      'definition', pg_catalog.pg_get_functiondef(procedure_entry.oid)
    )
    from pg_catalog.pg_proc as procedure_entry
    where procedure_entry.oid =
      'public.validate_east_malaysia_site(double precision,double precision,smallint)'::regprocedure
  ) as validator_state,
  (
    select pg_catalog.jsonb_build_object(
      'owner', relation.relowner,
      'acl', pg_catalog.to_jsonb(relation.relacl),
      'rls', relation.relrowsecurity,
      'force_rls', relation.relforcerowsecurity
    )
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.station_assessments'::regclass
  ) as assessment_relation_state,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', attribute_entry.attname,
          'acl', pg_catalog.to_jsonb(attribute_entry.attacl)
        )
        order by attribute_entry.attnum
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid = 'public.station_assessments'::regclass
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
  ) as assessment_column_acls,
  (
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
  ) as assessment_policies,
  (
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
  ) as assessment_triggers,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', relation.oid::regclass::text,
          'owner', relation.relowner,
          'acl', pg_catalog.to_jsonb(relation.relacl),
          'rls', relation.relrowsecurity,
          'force_rls', relation.relforcerowsecurity
        )
        order by relation.oid::regclass::text
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_class as relation
    where relation.oid in (
      'public.east_malaysia_boundary_datasets'::regclass,
      'public.east_malaysia_territory_boundaries'::regclass
    )
  ) as boundary_relation_states,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'table', relation.oid::regclass::text,
          'name', attribute_entry.attname,
          'acl', pg_catalog.to_jsonb(attribute_entry.attacl)
        )
        order by relation.oid::regclass::text, attribute_entry.attnum
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_attribute as attribute_entry
      on attribute_entry.attrelid = relation.oid
    where relation.oid in (
      'public.east_malaysia_boundary_datasets'::regclass,
      'public.east_malaysia_territory_boundaries'::regclass
    )
      and attribute_entry.attnum > 0
      and not attribute_entry.attisdropped
  ) as boundary_column_acls,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', procedure_entry.oid::regprocedure::text,
          'owner', procedure_entry.proowner,
          'security_definer', procedure_entry.prosecdef,
          'config', pg_catalog.to_jsonb(procedure_entry.proconfig),
          'acl', pg_catalog.to_jsonb(procedure_entry.proacl),
          'definition', pg_catalog.pg_get_functiondef(procedure_entry.oid)
        )
        order by procedure_entry.oid::regprocedure::text
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_proc as procedure_entry
    where procedure_entry.oid in (
      'public.current_assessment_company_id()'::regprocedure,
      'public.current_user_is_company_admin()'::regprocedure,
      'public.set_station_assessment_ownership()'::regprocedure,
      'public.prevent_station_assessment_ownership_change()'::regprocedure
    )
  ) as company_function_states,
  (
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(policy_entry)
        order by policy_entry.tablename, policy_entry.policyname
      ),
      '[]'::jsonb
    )
    from pg_catalog.pg_policies as policy_entry
    where policy_entry.schemaname = 'public'
      and policy_entry.tablename in (
        'east_malaysia_boundary_datasets',
        'east_malaysia_territory_boundaries'
      )
  ) as boundary_policies;

do $module2_validated_create_postconditions$
declare
  v_function regprocedure :=
    'public.create_validated_station_assessment(text,numeric,integer,integer,integer,numeric,integer,integer,integer,integer,numeric,text,text,text,double precision,double precision,smallint,uuid)'::regprocedure;
begin
  if exists (
    select 1
    from pg_temp.module2_validated_create_foundation_snapshot as before_state
    cross join pg_temp.module2_validated_create_foundation_post_state as after_state
    where row(
      before_state.assessment_rows,
      before_state.validator_state,
      before_state.assessment_relation_state,
      before_state.assessment_column_acls,
      before_state.assessment_policies,
      before_state.assessment_triggers,
      before_state.boundary_relation_states,
      before_state.boundary_column_acls,
      before_state.company_function_states,
      before_state.boundary_policies
    ) is distinct from row(
      after_state.assessment_rows,
      after_state.validator_state,
      after_state.assessment_relation_state,
      after_state.assessment_column_acls,
      after_state.assessment_policies,
      after_state.assessment_triggers,
      after_state.boundary_relation_states,
      after_state.boundary_column_acls,
      after_state.company_function_states,
      after_state.boundary_policies
    )
  ) then
    raise exception
      'Module 2 validated assessment creation changed protected foundation state';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure_entry.proowner
    where procedure_entry.oid = v_function
      and procedure_entry.proowner = (
        select role_entry.oid
        from pg_catalog.pg_roles as role_entry
        where role_entry.rolname = current_user
      )
      and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
      and procedure_entry.prosecdef
      and coalesce(procedure_entry.proconfig, '{}'::text[])
        @> array['search_path=""']::text[]
  ) then
    raise exception
      'Module 2 validated assessment creation function security metadata is invalid';
  end if;

  if exists (
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
  )
    or pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE')
    or not pg_catalog.has_function_privilege(
      'authenticated',
      v_function,
      'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'service_role',
      v_function,
      'EXECUTE'
    ) then
    raise exception
      'Module 2 validated assessment creation function ACL is invalid';
  end if;

  if exists (
    select 1
    from (
      values
        ('id'),
        ('company_id'),
        ('site_location'),
        ('analysis_radius_km'),
        ('geographic_validation_status'),
        ('confirmed_territory'),
        ('boundary_dataset_id'),
        ('geographically_validated_at'),
        ('created_at'),
        ('updated_at')
    ) as protected_column(column_name)
    where pg_catalog.has_column_privilege(
      'authenticated',
      'public.station_assessments',
      protected_column.column_name,
      'INSERT'
    )
      or pg_catalog.has_column_privilege(
        'authenticated',
        'public.station_assessments',
        protected_column.column_name,
        'UPDATE'
      )
  ) then
    raise exception
      'Module 2 validated assessment creation exposed a protected assessment column';
  end if;

  if pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'user_id',
    'UPDATE'
  ) then
    raise exception
      'Module 2 validated assessment creation exposed creator ownership updates';
  end if;
end;
$module2_validated_create_postconditions$;

drop table pg_temp.module2_validated_create_foundation_post_state;
drop table pg_temp.module2_validated_create_foundation_snapshot;
