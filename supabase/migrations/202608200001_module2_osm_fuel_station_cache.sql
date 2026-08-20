-- Private, server-maintained cache for fixed nearby OpenStreetMap fuel queries.
-- It avoids one Overpass request for every map pan or widget rebuild. Cache
-- entries contain public geographic evidence only: never user or company data.

do $module2_osm_cache_preconditions$
begin
  if exists (
    select 1
    from pg_catalog.pg_roles as role_entry
    where role_entry.rolname = current_user
      and role_entry.rolname in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception
      'Module 2 OSM cache migration must run as a non-API owner role';
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
    raise exception 'Module 2 OSM cache migration requires API roles';
  end if;

  if pg_catalog.to_regprocedure(
    'public.validate_east_malaysia_site(double precision,double precision,smallint)'
  ) is null then
    raise exception
      'Module 2 OSM cache migration requires the East Malaysia validator';
  end if;

  if pg_catalog.to_regnamespace('module2_private') is not null
    or pg_catalog.to_regclass(
    'module2_private.nearby_fuel_station_cache'
  ) is not null
    or pg_catalog.to_regprocedure(
      'public.nearby_fuel_station_cache_get(double precision,double precision,smallint)'
    ) is not null
    or pg_catalog.to_regprocedure(
      'public.nearby_fuel_station_cache_put(double precision,double precision,smallint,jsonb,jsonb)'
    ) is not null then
    raise exception 'Module 2 OSM cache target objects already exist';
  end if;
end;
$module2_osm_cache_preconditions$;

create schema module2_private authorization current_user;

revoke all privileges on schema module2_private
from public, anon, authenticated, service_role;

create function module2_private.is_valid_cache_double(
  p_value jsonb,
  p_minimum double precision,
  p_maximum double precision
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $module2_osm_cache_double_validation$
declare
  v_value double precision;
begin
  if p_value is null or pg_catalog.jsonb_typeof(p_value) <> 'number' then
    return false;
  end if;

  begin
    v_value := (p_value #>> '{}')::double precision;
  exception
    when data_exception then
      return false;
  end;

  return v_value not in (
    'NaN'::double precision,
    'Infinity'::double precision,
    '-Infinity'::double precision
  ) and v_value >= p_minimum and v_value <= p_maximum;
end;
$module2_osm_cache_double_validation$;

create function module2_private.is_valid_nearby_fuel_station_cache_result(
  p_result jsonb,
  p_latitude double precision,
  p_longitude double precision,
  p_analysis_radius_km smallint
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $module2_osm_cache_result_validation$
declare
  v_station_count integer;
  v_station jsonb;
begin
  if p_result is null
    or pg_catalog.jsonb_typeof(p_result) <> 'object'
    or (
      select pg_catalog.count(*)
      from pg_catalog.jsonb_object_keys(p_result)
    ) <> 10
    or not p_result ?& array[
      'source',
      'attribution',
      'attribution_url',
      'fetched_at',
      'analysis_radius_km',
      'latitude',
      'longitude',
      'station_count',
      'nearest_distance_km',
      'stations'
    ]::text[]
    or p_result ->> 'source' <> 'openstreetmap'
    or p_result ->> 'attribution' <> '© OpenStreetMap contributors'
    or p_result ->> 'attribution_url' <> 'https://www.openstreetmap.org/copyright'
    or pg_catalog.jsonb_typeof(p_result -> 'fetched_at') <> 'string'
    or not module2_private.is_valid_cache_double(
      p_result -> 'latitude', -90::double precision, 90::double precision
    )
    or not module2_private.is_valid_cache_double(
      p_result -> 'longitude', -180::double precision, 180::double precision
    )
    or p_result -> 'latitude' <> pg_catalog.to_jsonb(p_latitude)
    or p_result -> 'longitude' <> pg_catalog.to_jsonb(p_longitude)
    or pg_catalog.jsonb_typeof(p_result -> 'analysis_radius_km') <> 'number'
    or p_result -> 'analysis_radius_km' <> pg_catalog.to_jsonb(p_analysis_radius_km)
    or pg_catalog.jsonb_typeof(p_result -> 'station_count') <> 'number'
    or pg_catalog.jsonb_typeof(p_result -> 'stations') <> 'array' then
    return false;
  end if;

  begin
    v_station_count := (p_result ->> 'station_count')::integer;
  exception
    when data_exception then
      return false;
  end;

  if v_station_count < 0
    or v_station_count > 100
    or v_station_count <> pg_catalog.jsonb_array_length(p_result -> 'stations') then
    return false;
  end if;

  if (v_station_count = 0 and pg_catalog.jsonb_typeof(
      p_result -> 'nearest_distance_km'
    ) <> 'null')
    or (v_station_count > 0 and not module2_private.is_valid_cache_double(
      p_result -> 'nearest_distance_km', 0::double precision, 'Infinity'::double precision
    )) then
    return false;
  end if;

  for v_station in
    select station_entry.value
    from pg_catalog.jsonb_array_elements(p_result -> 'stations') as station_entry(value)
  loop
    if pg_catalog.jsonb_typeof(v_station) <> 'object'
      or (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_object_keys(v_station)
      ) <> 8
      or not v_station ?& array[
        'osm_type',
        'osm_id',
        'name',
        'brand',
        'operator',
        'latitude',
        'longitude',
        'distance_km'
      ]::text[]
      or pg_catalog.jsonb_typeof(v_station -> 'osm_type') <> 'string'
      or v_station ->> 'osm_type' not in ('node', 'way', 'relation')
      or pg_catalog.jsonb_typeof(v_station -> 'osm_id') <> 'string'
      or v_station ->> 'osm_id' !~ '^[1-9][0-9]*$'
      or pg_catalog.jsonb_typeof(v_station -> 'name') not in ('string', 'null')
      or pg_catalog.jsonb_typeof(v_station -> 'brand') not in ('string', 'null')
      or pg_catalog.jsonb_typeof(v_station -> 'operator') not in ('string', 'null')
      or not module2_private.is_valid_cache_double(
        v_station -> 'latitude', -90::double precision, 90::double precision
      )
      or not module2_private.is_valid_cache_double(
        v_station -> 'longitude', -180::double precision, 180::double precision
      )
      or not module2_private.is_valid_cache_double(
        v_station -> 'distance_km', 0::double precision, 'Infinity'::double precision
      ) then
      return false;
    end if;
  end loop;

  return true;
end;
$module2_osm_cache_result_validation$;

revoke all privileges on function module2_private.is_valid_cache_double(
  jsonb, double precision, double precision
) from public, anon, authenticated, service_role;

revoke all privileges on function module2_private.is_valid_nearby_fuel_station_cache_result(
  jsonb, double precision, double precision, smallint
) from public, anon, authenticated, service_role;

create table module2_private.nearby_fuel_station_cache (
  latitude double precision not null,
  longitude double precision not null,
  analysis_radius_km smallint not null,
  source_response jsonb not null,
  cached_result jsonb not null,
  fetched_at timestamptz not null,
  expires_at timestamptz not null,
  primary key (latitude, longitude, analysis_radius_km),
  constraint nearby_fuel_station_cache_latitude_check
    check (
      latitude between -90 and 90
      and latitude not in (
        'NaN'::double precision,
        'Infinity'::double precision,
        '-Infinity'::double precision
      )
    ),
  constraint nearby_fuel_station_cache_longitude_check
    check (
      longitude between -180 and 180
      and longitude not in (
        'NaN'::double precision,
        'Infinity'::double precision,
        '-Infinity'::double precision
      )
    ),
  constraint nearby_fuel_station_cache_radius_check
    check (analysis_radius_km in (3, 5, 10)),
  constraint nearby_fuel_station_cache_result_object_check
    check (
      pg_catalog.pg_column_size(cached_result) <= 1048576
      and module2_private.is_valid_nearby_fuel_station_cache_result(
        cached_result,
        latitude,
        longitude,
        analysis_radius_km
      )
    ),
  constraint nearby_fuel_station_cache_source_response_object_check
    check (
      pg_catalog.pg_column_size(source_response) <= 1048576
      and pg_catalog.jsonb_typeof(source_response) = 'object'
    ),
  constraint nearby_fuel_station_cache_ttl_check
    check (
      expires_at > fetched_at
      and expires_at = fetched_at + interval '24 hours'
    )
);

create index nearby_fuel_station_cache_expires_at_idx
on module2_private.nearby_fuel_station_cache (expires_at);

alter table module2_private.nearby_fuel_station_cache
enable row level security;

revoke all privileges on table module2_private.nearby_fuel_station_cache
from public, anon, authenticated, service_role;

create function public.nearby_fuel_station_cache_get(
  p_latitude double precision,
  p_longitude double precision,
  p_analysis_radius_km smallint
)
returns table (
  cached_result jsonb,
  fetched_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $module2_osm_cache_get$
declare
  v_latitude double precision;
  v_longitude double precision;
begin
  if p_latitude is null
    or p_latitude < -90
    or p_latitude > 90
    or p_latitude in (
      'NaN'::double precision,
      'Infinity'::double precision,
      '-Infinity'::double precision
    )
    or p_longitude is null
    or p_longitude < -180
    or p_longitude > 180
    or p_longitude in (
      'NaN'::double precision,
      'Infinity'::double precision,
      '-Infinity'::double precision
    )
    or p_analysis_radius_km is null
    or p_analysis_radius_km not in (3, 5, 10) then
    raise exception 'Nearby fuel-station cache parameters are invalid'
      using errcode = '22023';
  end if;

  v_latitude := case when p_latitude = 0 then 0::double precision else p_latitude end;
  v_longitude := case when p_longitude = 0 then 0::double precision else p_longitude end;

  return query
  select cache_entry.cached_result, cache_entry.fetched_at
  from module2_private.nearby_fuel_station_cache as cache_entry
  where cache_entry.latitude = v_latitude
    and cache_entry.longitude = v_longitude
    and cache_entry.analysis_radius_km = p_analysis_radius_km
    and cache_entry.expires_at > pg_catalog.now();
end;
$module2_osm_cache_get$;

create function public.nearby_fuel_station_cache_put(
  p_latitude double precision,
  p_longitude double precision,
  p_analysis_radius_km smallint,
  p_result jsonb,
  p_source_response jsonb
)
returns table (
  cached_result jsonb,
  fetched_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $module2_osm_cache_put$
declare
  v_latitude double precision;
  v_longitude double precision;
  v_fetched_at timestamptz := pg_catalog.now();
begin
  if p_latitude is null
    or p_latitude < -90
    or p_latitude > 90
    or p_latitude in (
      'NaN'::double precision,
      'Infinity'::double precision,
      '-Infinity'::double precision
    )
    or p_longitude is null
    or p_longitude < -180
    or p_longitude > 180
    or p_longitude in (
      'NaN'::double precision,
      'Infinity'::double precision,
      '-Infinity'::double precision
    )
    or p_analysis_radius_km is null
    or p_analysis_radius_km not in (3, 5, 10)
    or p_result is null
    or pg_catalog.jsonb_typeof(p_result) <> 'object'
    or p_source_response is null
    or pg_catalog.jsonb_typeof(p_source_response) <> 'object' then
    raise exception 'Nearby fuel-station cache parameters are invalid'
      using errcode = '22023';
  end if;

  v_latitude := case when p_latitude = 0 then 0::double precision else p_latitude end;
  v_longitude := case when p_longitude = 0 then 0::double precision else p_longitude end;

  -- The trusted server-side caller alone reaches this function. Pruning on
  -- write prevents expired keys accumulating. The exact composite primary key
  -- makes concurrent writes for an identical validated request conflict-safe.
  delete from module2_private.nearby_fuel_station_cache
  where expires_at <= v_fetched_at;

  return query
  insert into module2_private.nearby_fuel_station_cache as cache_entry (
    latitude,
    longitude,
    analysis_radius_km,
    source_response,
    cached_result,
    fetched_at,
    expires_at
  ) values (
    v_latitude,
    v_longitude,
    p_analysis_radius_km,
    p_source_response,
    p_result,
    v_fetched_at,
    v_fetched_at + interval '24 hours'
  )
  on conflict (latitude, longitude, analysis_radius_km) do update
  set latitude = excluded.latitude,
    longitude = excluded.longitude,
    analysis_radius_km = excluded.analysis_radius_km,
    source_response = excluded.source_response,
    cached_result = excluded.cached_result,
    fetched_at = excluded.fetched_at,
    expires_at = excluded.expires_at
  returning cache_entry.cached_result, cache_entry.fetched_at;
end;
$module2_osm_cache_put$;

revoke all privileges on function public.nearby_fuel_station_cache_get(
  double precision, double precision, smallint
) from public, anon, authenticated, service_role;

revoke all privileges on function public.nearby_fuel_station_cache_put(
  double precision, double precision, smallint, jsonb, jsonb
) from public, anon, authenticated, service_role;

grant execute on function public.nearby_fuel_station_cache_get(
  double precision, double precision, smallint
) to service_role;

grant execute on function public.nearby_fuel_station_cache_put(
  double precision, double precision, smallint, jsonb, jsonb
) to service_role;

do $module2_osm_cache_postconditions$
declare
  v_get_function regprocedure :=
    'public.nearby_fuel_station_cache_get(double precision,double precision,smallint)'::regprocedure;
  v_put_function regprocedure :=
    'public.nearby_fuel_station_cache_put(double precision,double precision,smallint,jsonb,jsonb)'::regprocedure;
  v_double_validation_function regprocedure :=
    'module2_private.is_valid_cache_double(jsonb,double precision,double precision)'::regprocedure;
  v_result_validation_function regprocedure :=
    'module2_private.is_valid_nearby_fuel_station_cache_result(jsonb,double precision,double precision,smallint)'::regprocedure;
  v_check record;
  v_has_privilege boolean;
begin
  if not exists (
    select 1
    from pg_catalog.pg_class as relation_entry
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation_entry.relnamespace
    where namespace.nspname = 'module2_private'
      and relation_entry.relname = 'nearby_fuel_station_cache'
      and relation_entry.relrowsecurity
  ) or exists (
    select 1
    from pg_catalog.pg_policy as policy_entry
    where policy_entry.polrelid =
      'module2_private.nearby_fuel_station_cache'::regclass
  ) then
    raise exception 'Module 2 OSM cache table must remain private with RLS';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute as attribute_entry
    where attribute_entry.attrelid =
      'module2_private.nearby_fuel_station_cache'::regclass
      and not attribute_entry.attisdropped
      and attribute_entry.attname in ('user_id', 'company_id')
  ) then
    raise exception 'Module 2 OSM cache must not store user or company data';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class as relation_entry
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        relation_entry.relacl,
        pg_catalog.acldefault('r', relation_entry.relowner)
      )
    ) as table_acl
    where relation_entry.oid =
      'module2_private.nearby_fuel_station_cache'::regclass
      and table_acl.grantee in (0::oid, 'anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)
      and table_acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'Module 2 OSM cache table must deny API table privileges';
  end if;

  for v_check in
    select checked_role.role_name, checked_privilege.privilege_name
    from (values ('PUBLIC'), ('anon'), ('authenticated'), ('service_role'))
      as checked_role(role_name)
    cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'))
      as checked_privilege(privilege_name)
  loop
    if v_check.role_name = 'PUBLIC' then
      select exists (
        select 1
        from pg_catalog.pg_class as relation_entry
        cross join lateral pg_catalog.aclexplode(
          coalesce(
            relation_entry.relacl,
            pg_catalog.acldefault('r', relation_entry.relowner)
          )
        ) as table_acl
        where relation_entry.oid =
          'module2_private.nearby_fuel_station_cache'::regclass
          and table_acl.grantee = 0
          and table_acl.privilege_type = v_check.privilege_name
      ) into v_has_privilege;
    else
      v_has_privilege := pg_catalog.has_table_privilege(
        v_check.role_name,
        'module2_private.nearby_fuel_station_cache',
        v_check.privilege_name
      );
    end if;

    if v_has_privilege then
      raise exception
        'Module 2 OSM cache must deny % table access to %',
        v_check.privilege_name,
        v_check.role_name;
    end if;
  end loop;

  if position(
    'p_analysis_radius_km is null' in
      pg_catalog.pg_get_functiondef(v_get_function)
  ) = 0 or position(
    'p_analysis_radius_km is null' in
      pg_catalog.pg_get_functiondef(v_put_function)
  ) = 0 then
    raise exception 'Module 2 OSM cache functions must reject NULL radii';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure_entry.proowner
    where procedure_entry.oid in (v_get_function, v_put_function)
      and (
        not procedure_entry.prosecdef
        or procedure_entry.proconfig is distinct from array['search_path=""']::text[]
        or owner_role.rolname <> current_user
        or owner_role.rolname in ('anon', 'authenticated', 'service_role')
      )
  ) or exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure_entry.proowner
    where procedure_entry.oid in (
      v_double_validation_function,
      v_result_validation_function
    ) and (
      procedure_entry.prosecdef
      or procedure_entry.proconfig is distinct from array['search_path=""']::text[]
      or owner_role.rolname <> current_user
      or owner_role.rolname in ('anon', 'authenticated', 'service_role')
    )
  ) or not pg_catalog.has_function_privilege(
    'service_role', v_get_function, 'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'service_role', v_put_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon', v_get_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated', v_get_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon', v_put_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated', v_put_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon', v_double_validation_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated', v_double_validation_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'service_role', v_double_validation_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon', v_result_validation_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated', v_result_validation_function, 'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'service_role', v_result_validation_function, 'EXECUTE'
  ) or exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        procedure_entry.proacl,
        pg_catalog.acldefault('f', procedure_entry.proowner)
      )
    ) as function_acl
    where procedure_entry.oid in (
      v_get_function,
      v_put_function,
      v_double_validation_function,
      v_result_validation_function
    )
      and function_acl.grantee = 0
      and function_acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'Module 2 OSM cache functions must be Edge-only';
  end if;
end;
$module2_osm_cache_postconditions$;
