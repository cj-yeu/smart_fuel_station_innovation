-- Transactional RLS/ACL tests for Module 3 advisory-only AI insights.
-- Run after migrations against an isolated Supabase/PostgreSQL database.

begin;

create temporary table module3_ai_insight_test_session_init (
  initialized boolean not null default true
) on commit drop;

create function pg_temp.assert_true(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
set search_path = ''
as $module3_ai_insight_assert$
begin
  if p_condition is distinct from true then
    raise exception 'Module 3 AI insight assertion failed: %', p_message;
  end if;
end;
$module3_ai_insight_assert$;

do $module3_ai_insight_temp_grants$
declare
  v_temp_schema text;
begin
  select namespace.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace
  where namespace.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception 'Module 3 AI insight temporary schema was not initialized';
  end if;

  execute pg_catalog.format(
    'grant usage on schema %I to authenticated, anon, service_role',
    v_temp_schema
  );
  execute pg_catalog.format(
    'grant execute on function %I.assert_true(boolean, text) to authenticated, anon, service_role',
    v_temp_schema
  );
end;
$module3_ai_insight_temp_grants$;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '71000000-0000-4000-8000-000000000001',
    'module3-ai-insight-owner@example.invalid',
    '{}'::jsonb
  ),
  (
    '71000000-0000-4000-8000-000000000002',
    'module3-ai-insight-other@example.invalid',
    '{}'::jsonb
  );

insert into public.business_evaluations (
  id,
  user_id,
  station_name,
  fuel_price,
  fuel_purchase_cost,
  daily_customers,
  average_litres,
  monthly_rental,
  monthly_staff_salary,
  monthly_utilities,
  monthly_maintenance,
  monthly_other_cost,
  initial_investment,
  monthly_sales_volume,
  monthly_revenue,
  monthly_fuel_cost,
  monthly_operating_cost,
  monthly_profit,
  profit_margin,
  roi,
  break_even_months,
  profitability_score,
  profitability_category,
  recommendation,
  explanation
)
values (
  '72000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  'Module 3 AI Insight Test Station',
  2.95,
  2.20,
  500,
  35,
  20000,
  30000,
  5000,
  4000,
  2000,
  2000000,
  525000,
  1548750,
  1155000,
  1216000,
  332750,
  21.49,
  199.65,
  6.01,
  88.5,
  'Profitable',
  'The proposed fuel station shows strong financial potential.',
  'Deterministic calculation summary.'
);

set local role service_role;

insert into public.business_evaluation_ai_insights (
  evaluation_id,
  user_id,
  insight,
  model,
  prompt_version,
  input_hash,
  source_evaluation_updated_at,
  generated_at
)
select
  evaluation.id,
  -- The trigger must replace this deliberately incorrect value with the
  -- evaluation owner before the non-null/foreign-key constraints are checked.
  '71000000-0000-4000-8000-000000000002',
  '{
    "executive_summary":"Advisory-only deterministic explanation.",
    "drivers":[],
    "actions":[],
    "scenario_to_test":{"variable":"daily_customers","direction":"review","reason":"Test only."},
    "data_limitations":[],
    "disclaimer":"Decision-support only."
  }'::jsonb,
  'gpt-5.6-sol',
  'module3-business-advisor-v1',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  evaluation.updated_at,
  pg_catalog.now()
from public.business_evaluations as evaluation
where evaluation.id = '72000000-0000-4000-8000-000000000001';

select pg_temp.assert_true(
  (
    select insight.user_id = evaluation.user_id
    from public.business_evaluation_ai_insights as insight
    join public.business_evaluations as evaluation
      on evaluation.id = insight.evaluation_id
    where insight.evaluation_id = '72000000-0000-4000-8000-000000000001'
  ),
  'the ownership trigger must derive user_id from business_evaluations'
);

reset role;

select pg_temp.assert_true(
  pg_catalog.has_table_privilege(
    'authenticated',
    'public.business_evaluation_ai_insights',
    'SELECT'
  )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.business_evaluation_ai_insights',
      'INSERT'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.business_evaluation_ai_insights',
      'UPDATE'
    )
    and not pg_catalog.has_table_privilege(
      'authenticated',
      'public.business_evaluation_ai_insights',
      'DELETE'
    )
    and not pg_catalog.has_table_privilege(
      'anon',
      'public.business_evaluation_ai_insights',
      'SELECT'
    ),
  'only authenticated SELECT access may be granted to application clients'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '71000000-0000-4000-8000-000000000001',
  true
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
    from public.business_evaluation_ai_insights
  ),
  'the evaluation owner must read their AI insight'
);

do $module3_ai_insight_authenticated_write_denial$
begin
  update public.business_evaluation_ai_insights
  set prompt_version = 'client-attempt'
  where evaluation_id = '72000000-0000-4000-8000-000000000001';
  raise exception 'Expected authenticated direct update to fail';
exception
  when insufficient_privilege then null;
end;
$module3_ai_insight_authenticated_write_denial$;

do $module3_ai_insight_authenticated_insert_denial$
begin
  insert into public.business_evaluation_ai_insights (
    evaluation_id,
    user_id,
    insight,
    model,
    prompt_version,
    input_hash,
    source_evaluation_updated_at,
    generated_at
  ) values (
    '72000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    '{}'::jsonb,
    'gpt-5.6-sol',
    'module3-business-advisor-v1',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    pg_catalog.now(),
    pg_catalog.now()
  );
  raise exception 'Expected authenticated direct insert to fail';
exception
  when insufficient_privilege then null;
end;
$module3_ai_insight_authenticated_insert_denial$;

do $module3_ai_insight_authenticated_delete_denial$
begin
  delete from public.business_evaluation_ai_insights
  where evaluation_id = '72000000-0000-4000-8000-000000000001';
  raise exception 'Expected authenticated direct delete to fail';
exception
  when insufficient_privilege then null;
end;
$module3_ai_insight_authenticated_delete_denial$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '71000000-0000-4000-8000-000000000002',
  true
);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 0
    from public.business_evaluation_ai_insights
  ),
  'another authenticated user must not read the owner AI insight'
);

reset role;
set local role anon;

do $module3_ai_insight_anon_select_denial$
begin
  perform pg_catalog.count(*)
  from public.business_evaluation_ai_insights;
  raise exception 'Expected anon AI insight select to fail';
exception
  when insufficient_privilege then null;
end;
$module3_ai_insight_anon_select_denial$;

reset role;

set local role service_role;

do $module3_ai_insight_one_to_one$
declare
  v_source_updated_at timestamptz;
begin
  select evaluation.updated_at
  into strict v_source_updated_at
  from public.business_evaluations as evaluation
  where evaluation.id = '72000000-0000-4000-8000-000000000001';

  begin
    insert into public.business_evaluation_ai_insights (
      evaluation_id,
      user_id,
      insight,
      model,
      prompt_version,
      input_hash,
      source_evaluation_updated_at,
      generated_at
    ) values (
      '72000000-0000-4000-8000-000000000001',
      '71000000-0000-4000-8000-000000000001',
      '{}'::jsonb,
      'gpt-5.6-sol',
      'module3-business-advisor-v1',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      v_source_updated_at,
      pg_catalog.now()
    );
    raise exception 'Expected one-to-one insight duplicate to fail';
  exception
    when unique_violation then null;
  end;
end;
$module3_ai_insight_one_to_one$;

reset role;

delete from public.business_evaluations
where id = '72000000-0000-4000-8000-000000000001';

set local role service_role;

select pg_temp.assert_true(
  not exists (
    select 1
    from public.business_evaluation_ai_insights
    where evaluation_id = '72000000-0000-4000-8000-000000000001'
  ),
  'deleting an evaluation must cascade-delete its AI insight'
);

reset role;

rollback;
