-- Advisory-only AI insights for existing, deterministic Module 3 evaluations.
-- BusinessEvaluationService remains the sole authority for every calculation,
-- score, category, recommendation, and calculation summary.

do $module3_ai_insight_preconditions$
begin
  if exists (
    select 1
    from pg_catalog.pg_roles as role_entry
    where role_entry.rolname = current_user
      and role_entry.rolname in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception
      'Module 3 AI insight migration must run as a non-API owner role';
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
    raise exception 'Module 3 AI insight migration requires API roles';
  end if;

  if pg_catalog.to_regclass('public.business_evaluations') is null then
    raise exception
      'Module 3 AI insight migration requires public.business_evaluations';
  end if;

  if pg_catalog.to_regclass('public.business_evaluation_ai_insights') is not null
    or pg_catalog.to_regprocedure(
      'public.enforce_business_evaluation_ai_insight_ownership()'
    ) is not null then
    raise exception 'Module 3 AI insight target objects already exist';
  end if;
end;
$module3_ai_insight_preconditions$;

create function public.enforce_business_evaluation_ai_insight_ownership()
returns trigger
language plpgsql
set search_path = ''
as $module3_ai_insight_ownership$
declare
  v_evaluation_user_id uuid;
  v_evaluation_updated_at timestamptz;
begin
  if tg_op = 'UPDATE'
    and old.evaluation_id is distinct from new.evaluation_id then
    raise exception 'An AI insight cannot be moved to another evaluation'
      using errcode = '22023';
  end if;

  select evaluation.user_id, evaluation.updated_at
  into strict v_evaluation_user_id, v_evaluation_updated_at
  from public.business_evaluations as evaluation
  where evaluation.id = new.evaluation_id;

  new.user_id := v_evaluation_user_id;

  if new.source_evaluation_updated_at is distinct from v_evaluation_updated_at then
    raise exception
      'AI insight source timestamp must match the current evaluation timestamp'
      using errcode = '22023';
  end if;

  return new;
exception
  when no_data_found then
    raise exception 'AI insight evaluation does not exist' using errcode = '23503';
end;
$module3_ai_insight_ownership$;

revoke all privileges on function public.enforce_business_evaluation_ai_insight_ownership()
from public, anon, authenticated, service_role;

create table public.business_evaluation_ai_insights (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null unique
    references public.business_evaluations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  insight jsonb not null,
  model text not null,
  prompt_version text not null,
  input_hash text not null,
  source_evaluation_updated_at timestamptz not null,
  generated_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint business_evaluation_ai_insights_insight_object_check
    check (pg_catalog.jsonb_typeof(insight) = 'object'),
  constraint business_evaluation_ai_insights_model_check
    check (model = 'gpt-5.6-sol'),
  constraint business_evaluation_ai_insights_prompt_version_check
    check (prompt_version ~ '^[A-Za-z0-9._-]{1,80}$'),
  constraint business_evaluation_ai_insights_input_hash_check
    check (input_hash ~ '^[0-9a-f]{64}$')
);

create index business_evaluation_ai_insights_user_id_idx
on public.business_evaluation_ai_insights (user_id);

create trigger enforce_business_evaluation_ai_insight_ownership
before insert or update on public.business_evaluation_ai_insights
for each row
execute function public.enforce_business_evaluation_ai_insight_ownership();

create trigger update_business_evaluation_ai_insights_updated_at
before update on public.business_evaluation_ai_insights
for each row
execute function public.update_updated_at_column();

alter table public.business_evaluation_ai_insights enable row level security;
alter table public.business_evaluation_ai_insights force row level security;

create policy "Users can view own business evaluation AI insights"
on public.business_evaluation_ai_insights
for select
to authenticated
using (auth.uid() = user_id);

revoke all privileges on table public.business_evaluation_ai_insights
from public, anon, authenticated, service_role;

grant select on table public.business_evaluation_ai_insights to authenticated;
grant select, insert, update on table public.business_evaluation_ai_insights
to service_role;

do $module3_ai_insight_postconditions$
declare
  v_table regclass := 'public.business_evaluation_ai_insights'::regclass;
  v_ownership_function regprocedure :=
    'public.enforce_business_evaluation_ai_insight_ownership()'::regprocedure;
begin
  if not exists (
    select 1
    from pg_catalog.pg_class as relation_entry
    where relation_entry.oid = v_table
      and relation_entry.relrowsecurity
      and relation_entry.relforcerowsecurity
  ) then
    raise exception 'Module 3 AI insights must enforce RLS';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policy as policy_entry
    where policy_entry.polrelid = v_table
  ) <> 1 or not exists (
    select 1
    from pg_catalog.pg_policy as policy_entry
    where policy_entry.polrelid = v_table
      and policy_entry.polname =
        'Users can view own business evaluation AI insights'
      and policy_entry.polcmd = 'r'
      and policy_entry.polroles = array['authenticated'::regrole::oid]
  ) then
    raise exception 'Module 3 AI insights must have only the own-row SELECT policy';
  end if;

  if not pg_catalog.has_table_privilege(
      'authenticated', v_table, 'SELECT'
    )
    or pg_catalog.has_table_privilege('authenticated', v_table, 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', v_table, 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', v_table, 'DELETE')
    or pg_catalog.has_table_privilege('anon', v_table, 'SELECT')
    or pg_catalog.has_table_privilege('anon', v_table, 'INSERT')
    or pg_catalog.has_table_privilege('anon', v_table, 'UPDATE')
    or pg_catalog.has_table_privilege('anon', v_table, 'DELETE')
    or not pg_catalog.has_table_privilege('service_role', v_table, 'SELECT')
    or not pg_catalog.has_table_privilege('service_role', v_table, 'INSERT')
    or not pg_catalog.has_table_privilege('service_role', v_table, 'UPDATE')
    or pg_catalog.has_table_privilege('service_role', v_table, 'DELETE') then
    raise exception 'Module 3 AI insight table privileges are incorrect';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_entry
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure_entry.proowner
    where procedure_entry.oid = v_ownership_function
      and (
        procedure_entry.prosecdef
        or procedure_entry.proconfig is distinct from array['search_path=""']::text[]
        or owner_role.rolname <> current_user
        or owner_role.rolname in ('anon', 'authenticated', 'service_role')
      )
  ) then
    raise exception 'Module 3 AI insight ownership trigger must remain owner-safe';
  end if;

  if pg_catalog.has_function_privilege(
      'anon', v_ownership_function, 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'authenticated', v_ownership_function, 'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'service_role', v_ownership_function, 'EXECUTE'
    ) then
    raise exception 'Module 3 AI insight trigger helper must not be API-callable';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_entry
    where constraint_entry.conrelid = v_table
      and constraint_entry.contype = 'u'
      and constraint_entry.conkey = array[
        (
          select attribute_entry.attnum
          from pg_catalog.pg_attribute as attribute_entry
          where attribute_entry.attrelid = v_table
            and attribute_entry.attname = 'evaluation_id'
        )
      ]::smallint[]
  ) then
    raise exception 'Module 3 AI insights must be one-to-one with evaluations';
  end if;
end;
$module3_ai_insight_postconditions$;
