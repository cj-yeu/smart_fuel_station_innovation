-- Transactional, framework-free tests for Module 2 company assessment RLS.
-- Run only against an isolated local Supabase/PostgreSQL database after all
-- migrations have been applied. The final rollback preserves the database.

begin;

-- Some SQL Editor sessions do not materialize pg_temp until the first
-- temporary object is created. This test-only table initializes that namespace
-- before pg_temp.assert_true and pg_temp.insert_assessment are created; the
-- final rollback removes it.
create temporary table module2_rls_test_session_init (
  initialized boolean not null default true
)
on commit drop;

create function pg_temp.assert_true(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_condition is distinct from true then
    raise exception 'Module 2 RLS assertion failed: %', p_message;
  end if;
end;
$$;

create function pg_temp.insert_assessment(
  p_location_name text,
  p_user_id uuid default null
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
    'Moderate',
    'Test recommendation',
    'Test explanation'
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$$;

-- This separate helper is used only to prove the company_id column ACL and
-- ownership trigger independently. Normal client-shaped inserts never include
-- company_id.
create function pg_temp.insert_assessment_with_company_for_test(
  p_location_name text,
  p_user_id uuid,
  p_company_id uuid
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
    explanation
  )
  values (
    p_user_id,
    p_company_id,
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
    'Moderate',
    'Test recommendation',
    'Test explanation'
  )
  returning id into v_assessment_id;

  return v_assessment_id;
end;
$$;

-- SET ROLE changes the effective database role inside this session. Grant only
-- the temporary helper access needed by the simulated API roles; rollback and
-- session teardown remove these temporary objects and grants.
do $$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception 'Module 2 RLS test temporary schema was not initialized';
  end if;

  execute pg_catalog.format(
    'grant usage on schema %I to authenticated, anon',
    v_temp_schema
  );

  execute pg_catalog.format(
    'grant execute on function %I.assert_true(boolean, text) to authenticated',
    v_temp_schema
  );

  execute pg_catalog.format(
    'grant execute on function %I.insert_assessment(text, uuid) to authenticated, anon',
    v_temp_schema
  );

  execute pg_catalog.format(
    'grant execute on function %I.insert_assessment_with_company_for_test(text, uuid, uuid) to authenticated',
    v_temp_schema
  );
end;
$$;

-- Synthetic fixture identifiers only; these are not production users or data.
insert into public.fuel_companies (
  id,
  company_code,
  company_name
)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'MODULE2_TEST_A',
    'Module 2 Test Company A'
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'MODULE2_TEST_B',
    'Module 2 Test Company B'
  );

insert into auth.users (
  id,
  email,
  raw_user_meta_data
)
values
  (
    '20000000-0000-0000-0000-000000000101',
    'module2-user-a1@example.invalid',
    '{"full_name":"Module 2 User A1"}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-000000000102',
    'module2-user-a2@example.invalid',
    '{"full_name":"Module 2 User A2"}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-000000000103',
    'module2-admin-a@example.invalid',
    '{"full_name":"Module 2 Admin A"}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-000000000201',
    'module2-user-b@example.invalid',
    '{"full_name":"Module 2 User B"}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-000000000202',
    'module2-admin-b@example.invalid',
    '{"full_name":"Module 2 Admin B"}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-000000000301',
    'module2-no-company@example.invalid',
    '{"full_name":"Module 2 No Company"}'::jsonb
  );

update public.profiles
set
  company_id = '10000000-0000-0000-0000-000000000001',
  role = case
    when user_id = '20000000-0000-0000-0000-000000000103'
      then 'company_admin'
    else 'company_user'
  end
where user_id in (
  '20000000-0000-0000-0000-000000000101',
  '20000000-0000-0000-0000-000000000102',
  '20000000-0000-0000-0000-000000000103'
);

update public.profiles
set
  company_id = '10000000-0000-0000-0000-000000000002',
  role = case
    when user_id = '20000000-0000-0000-0000-000000000202'
      then 'company_admin'
    else 'company_user'
  end
where user_id in (
  '20000000-0000-0000-0000-000000000201',
  '20000000-0000-0000-0000-000000000202'
);

-- Inspect effective ACLs directly so inherited PUBLIC or legacy column grants
-- cannot silently restore ownership updates outside the intended allowlist.
select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'user_id',
    'UPDATE'
  ),
  'authenticated must not have UPDATE privilege on user_id'
);

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'company_id',
    'UPDATE'
  ),
  'authenticated must not have UPDATE privilege on company_id'
);

select pg_temp.assert_true(
  pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'recommendation',
    'UPDATE'
  ),
  'authenticated must have UPDATE privilege on approved editable columns'
);

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'anon',
    'public.station_assessments',
    'user_id',
    'UPDATE'
  ),
  'anon must not have UPDATE privilege on user_id'
);

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'anon',
    'public.station_assessments',
    'company_id',
    'UPDATE'
  ),
  'anon must not have UPDATE privilege on company_id'
);

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'anon',
    'public.station_assessments',
    'recommendation',
    'UPDATE'
  ),
  'anon must not have UPDATE privilege on approved editable columns'
);

-- Insert normal fixtures through the authenticated path so ownership triggers
-- and INSERT RLS are exercised rather than bypassed.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000101',
  true
);
select pg_temp.insert_assessment(
  'A1 shared read and update',
  '20000000-0000-0000-0000-000000000101'
);
select pg_temp.insert_assessment('A1 delete own');

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000102',
  true
);
select pg_temp.insert_assessment('A2 shared admin target');
select pg_temp.insert_assessment('A2 delete admin target');

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000201',
  true
);
select pg_temp.insert_assessment('B user protected row');
select pg_temp.insert_assessment('B delete protected row');

reset role;

-- Simulate an unresolved pre-migration legacy row under explicit privileged
-- maintenance. Production maintenance must use the same deliberate trigger
-- disable/repair/re-enable pattern; authenticated policies are not weakened.
alter table public.station_assessments
disable trigger set_station_assessment_ownership;

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
  explanation
)
values (
  '20000000-0000-0000-0000-000000000301',
  null,
  'Unresolved legacy assessment',
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
  'Moderate',
  'Legacy test recommendation',
  'Legacy test explanation'
);

alter table public.station_assessments
enable trigger set_station_assessment_ownership;

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'Unresolved legacy assessment'
      and company_id is null
  ),
  'unresolved legacy rows must remain preserved with null company ownership'
);

select pg_temp.assert_true(
  (
    select is_nullable = 'YES'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'station_assessments'
      and column_name = 'company_id'
  ),
  'company_id must remain nullable for unresolved legacy rows'
);

-- Insert ownership is derived from auth.uid() and profiles.company_id.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'A1 shared read and update'
      and user_id = '20000000-0000-0000-0000-000000000101'
      and company_id = '10000000-0000-0000-0000-000000000001'
  ),
  'insert ownership must resolve to the authenticated user and profile company'
);

-- Same-company members read one another's assessments; other-company and
-- unresolved legacy rows remain invisible.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000101',
  true
);
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'A2 shared admin target'
  ),
  'same-company users must read each other''s assessments'
);
select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.station_assessments
    where location_name = 'B user protected row'
  ),
  'different-company assessments must not be readable'
);
select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.station_assessments
    where location_name = 'Unresolved legacy assessment'
  ),
  'unresolved legacy rows must not be exposed to company members'
);

-- A normal user updates their own row but not another same-company row.
select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'A1 updated own row'
      where location_name = 'A1 shared read and update'
      returning 1
    )
    select count(*) = 1 from changed
  ),
  'normal users must update their own assessments'
);
select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'A1 must not update A2'
      where location_name = 'A2 shared admin target'
      returning 1
    )
    select count(*) = 0 from changed
  ),
  'normal users must not update another same-company assessment'
);

-- A normal user deletes their own row but not another same-company row.
select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'A1 delete own'
      returning 1
    )
    select count(*) = 1 from removed
  ),
  'normal users must delete their own assessments'
);
select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'A2 delete admin target'
      returning 1
    )
    select count(*) = 0 from removed
  ),
  'normal users must not delete another same-company assessment'
);

-- Supplying another creator cannot create transferred ownership. This conflict
-- reaches and is rejected by the ownership trigger.
do $$
begin
  perform pg_temp.insert_assessment(
    'Invalid transferred creator',
    '20000000-0000-0000-0000-000000000102'
  );
  raise exception 'Expected transferred creator insert to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

-- A normal authenticated client cannot submit company_id because the column
-- ACL rejects it before ownership derivation is considered.
select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'company_id',
    'INSERT'
  ),
  'authenticated must not have company_id INSERT privilege'
);

do $$
begin
  perform pg_temp.insert_assessment_with_company_for_test(
    'Invalid transferred company ACL',
    '20000000-0000-0000-0000-000000000101',
    '10000000-0000-0000-0000-000000000002'
  );
  raise exception 'Expected client-supplied company_id insert ACL to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.station_assessments
    where location_name = 'Invalid transferred company ACL'
  ),
  'company_id INSERT ACL rejection must not create an assessment'
);

-- Temporarily expose only company_id INSERT so the immutable ownership trigger
-- is tested as an independent second layer, then restore and verify the ACL.
grant insert (company_id)
on public.station_assessments
to authenticated;

select pg_temp.assert_true(
  pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'company_id',
    'INSERT'
  ),
  'trigger-layer test requires temporary company_id INSERT privilege'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000101',
  true
);

do $$
begin
  perform pg_temp.insert_assessment_with_company_for_test(
    'Invalid transferred company trigger',
    '20000000-0000-0000-0000-000000000101',
    '10000000-0000-0000-0000-000000000002'
  );
  raise exception 'Expected ownership trigger to reject transferred company';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

revoke insert (company_id)
on public.station_assessments
from authenticated;

select pg_temp.assert_true(
  not pg_catalog.has_column_privilege(
    'authenticated',
    'public.station_assessments',
    'company_id',
    'INSERT'
  ),
  'authenticated company_id INSERT privilege must be revoked after trigger test'
);

select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.station_assessments
    where location_name = 'Invalid transferred company trigger'
  ),
  'ownership-trigger rejection must not create a transferred assessment'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000101',
  true
);

-- Ownership columns cannot be updated directly. Column privileges reject the
-- request; the ownership trigger remains a second line of defence.
do $$
begin
  update public.station_assessments
  set user_id = '20000000-0000-0000-0000-000000000102'
  where location_name = 'A1 shared read and update';
  raise exception 'Expected creator ownership update to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  update public.station_assessments
  set company_id = '10000000-0000-0000-0000-000000000002'
  where location_name = 'A1 shared read and update';
  raise exception 'Expected company ownership update to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- A same-company admin updates/deletes another member's rows, but cannot
-- affect a different company's rows and cannot assign another creator.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000103',
  true
);
select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Admin A updated A2 row'
      where location_name = 'A2 shared admin target'
      returning 1
    )
    select count(*) = 1 from changed
  ),
  'company admins must update another user''s same-company assessment'
);
select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'Admin A must not update B'
      where location_name = 'B user protected row'
      returning 1
    )
    select count(*) = 0 from changed
  ),
  'company admins must not update another company''s assessment'
);
select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'A2 delete admin target'
      returning 1
    )
    select count(*) = 1 from removed
  ),
  'company admins must delete another user''s same-company assessment'
);
select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where location_name = 'B delete protected row'
      returning 1
    )
    select count(*) = 0 from removed
  ),
  'company admins must not delete another company''s assessment'
);

do $$
begin
  perform pg_temp.insert_assessment(
    'Admin invalid creator assignment',
    '20000000-0000-0000-0000-000000000102'
  );
  raise exception 'Expected admin creator assignment to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  update public.station_assessments
  set company_id = '10000000-0000-0000-0000-000000000002'
  where location_name = 'A2 shared admin target';
  raise exception 'Expected admin company transfer to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- A profile without authoritative membership sees no assessments and cannot
-- insert, update, or delete. Capture an existing synthetic assessment ID while
-- privileged so the restricted checks target a known row by primary key.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'B user protected row'
  ),
  'the no-company RLS target assessment must exist before access checks'
);

select pg_catalog.set_config(
  'module2_test.no_company_target_id',
  (
    select id::text
    from public.station_assessments
    where location_name = 'B user protected row'
  ),
  true
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000301',
  true
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.station_assessments),
  'users without company membership must not read assessments'
);

do $$
begin
  perform pg_temp.insert_assessment('No-company invalid insert');
  raise exception 'Expected no-company insert to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

select pg_temp.assert_true(
  (
    with changed as (
      update public.station_assessments
      set recommendation = 'No-company user must not update'
      where id = pg_catalog.current_setting(
        'module2_test.no_company_target_id'
      )::uuid
      returning 1
    )
    select count(*) = 0 from changed
  ),
  'users without company membership must not update assessments'
);

select pg_temp.assert_true(
  (
    with removed as (
      delete from public.station_assessments
      where id = pg_catalog.current_setting(
        'module2_test.no_company_target_id'
      )::uuid
      returning 1
    )
    select count(*) = 0 from removed
  ),
  'users without company membership must not delete assessments'
);

reset role;

select pg_temp.assert_true(
  (
    select recommendation = 'Test recommendation'
    from public.station_assessments
    where id = pg_catalog.current_setting(
      'module2_test.no_company_target_id'
    )::uuid
  ),
  'rejected no-company update must leave the assessment unchanged'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where id = pg_catalog.current_setting(
      'module2_test.no_company_target_id'
    )::uuid
  ),
  'rejected no-company delete must leave the assessment row present'
);

-- The unauthenticated role has no table privileges. All CRUD attempts are
-- rejected rather than relying only on the absence of an anon RLS policy.
set local role anon;
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $$
begin
  perform count(*) from public.station_assessments;
  raise exception 'Expected unauthenticated read to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  perform pg_temp.insert_assessment('Unauthenticated invalid insert');
  raise exception 'Expected unauthenticated insert to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  update public.station_assessments
  set recommendation = 'Unauthenticated invalid update';
  raise exception 'Expected unauthenticated update to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  delete from public.station_assessments;
  raise exception 'Expected unauthenticated delete to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

reset role;

-- Even a privileged maintenance role does not silently bypass the ownership
-- trigger. A reviewed repair must explicitly disable the named trigger.
do $$
begin
  update public.station_assessments
  set user_id = '20000000-0000-0000-0000-000000000102'
  where location_name = 'A1 shared read and update';
  raise exception 'Expected privileged creator transfer to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

do $$
begin
  update public.station_assessments
  set company_id = '10000000-0000-0000-0000-000000000002'
  where location_name = 'A1 shared read and update';
  raise exception 'Expected privileged company transfer to fail';
exception
  when sqlstate '42501' then null;
end;
$$;

-- Reconfirm that rejected ownership attempts did not mutate stored ownership.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'A1 shared read and update'
      and user_id = '20000000-0000-0000-0000-000000000101'
      and company_id = '10000000-0000-0000-0000-000000000001'
  ),
  'rejected ownership changes must leave creator and company unchanged'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.station_assessments
    where location_name = 'Unresolved legacy assessment'
      and company_id is null
  ),
  'unresolved legacy rows must still exist after all access checks'
);

rollback;
