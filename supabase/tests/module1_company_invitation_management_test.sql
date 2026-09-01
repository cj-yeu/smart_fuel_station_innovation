-- Transactional security and behavior checks for Module 1 invitation management.
-- Run after migrations against an isolated Supabase/PostgreSQL database.

begin;

-- Some SQL Editor sessions create the real session temp namespace only after
-- the first temporary object. This test-only table initializes it before the
-- pg_temp helpers are created; the final rollback removes everything here.
create temporary table module1_invitation_management_test_session_init (
  initialized boolean not null default true
) on commit drop;

create function pg_temp.assert_true(
  p_condition boolean,
  p_message text
)
returns void
language plpgsql
set search_path = ''
as $module1_invitation_management_assert$
begin
  if p_condition is distinct from true then
    raise exception 'Module 1 invitation management assertion failed: %', p_message;
  end if;
end;
$module1_invitation_management_assert$;

create temporary table module1_invitation_management_generated_codes (
  label text primary key,
  invitation_id uuid not null,
  raw_code text not null
) on commit drop;

do $module1_invitation_management_temp_grants$
declare
  v_temp_schema text;
begin
  select namespace_entry.nspname
  into v_temp_schema
  from pg_catalog.pg_namespace as namespace_entry
  where namespace_entry.oid = pg_catalog.pg_my_temp_schema();

  if v_temp_schema is null then
    raise exception 'Module 1 invitation management temporary schema was not initialized';
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
    'grant select, insert on table %I.module1_invitation_management_generated_codes to authenticated',
    v_temp_schema
  );
end;
$module1_invitation_management_temp_grants$;

-- Synthetic identities. The auth.users trigger creates profiles, after which
-- the service role assigns authoritative company membership for this test.
set local role service_role;

insert into public.fuel_companies (id, company_code, company_name)
values
  (
    '11000000-0000-4000-8000-000000000001',
    'MODULE1INVITEA',
    'Module 1 Invitation Company A'
  ),
  (
    '11000000-0000-4000-8000-000000000002',
    'MODULE1INVITEB',
    'Module 1 Invitation Company B'
  );

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '12000000-0000-4000-8000-000000000001',
    'module1-invitation-admin-a@example.invalid',
    '{}'::jsonb
  ),
  (
    '12000000-0000-4000-8000-000000000002',
    'module1-invitation-user-a@example.invalid',
    '{}'::jsonb
  ),
  (
    '12000000-0000-4000-8000-000000000003',
    'module1-invitation-admin-b@example.invalid',
    '{}'::jsonb
  ),
  (
    '12000000-0000-4000-8000-000000000004',
    'module1-invitation-claim-user@example.invalid',
    '{}'::jsonb
  ),
  (
    '12000000-0000-4000-8000-000000000005',
    'module1-invitation-expired-user@example.invalid',
    '{}'::jsonb
  ),
  (
    '12000000-0000-4000-8000-000000000006',
    'module1-invitation-limited-user@example.invalid',
    '{}'::jsonb
  );

update public.profiles
set
  company_id = case user_id
    when '12000000-0000-4000-8000-000000000001'::uuid
      then '11000000-0000-4000-8000-000000000001'::uuid
    when '12000000-0000-4000-8000-000000000002'::uuid
      then '11000000-0000-4000-8000-000000000001'::uuid
    when '12000000-0000-4000-8000-000000000003'::uuid
      then '11000000-0000-4000-8000-000000000002'::uuid
    else null
  end,
  role = case user_id
    when '12000000-0000-4000-8000-000000000001'::uuid then 'company_admin'
    when '12000000-0000-4000-8000-000000000003'::uuid then 'company_admin'
    else 'company_user'
  end
where user_id in (
  '12000000-0000-4000-8000-000000000001'::uuid,
  '12000000-0000-4000-8000-000000000002'::uuid,
  '12000000-0000-4000-8000-000000000003'::uuid,
  '12000000-0000-4000-8000-000000000004'::uuid,
  '12000000-0000-4000-8000-000000000005'::uuid,
  '12000000-0000-4000-8000-000000000006'::uuid
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000001',
  true
);

-- The management RPC never accepts a company identifier; company membership
-- comes only from the authoritative caller profile.
select pg_temp.assert_true(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'create_company_invitation_code'
  ) = 1
  and exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'create_company_invitation_code'
      and function_entry.prokind = 'f'
      and function_entry.oid = pg_catalog.to_regprocedure(
        'public.create_company_invitation_code(integer,integer)'
      )
      and function_entry.pronargs = 2
      and function_entry.proargtypes[0] =
        'pg_catalog.int4'::pg_catalog.regtype
      and function_entry.proargtypes[1] =
        'pg_catalog.int4'::pg_catalog.regtype
  )
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'list_company_invitation_codes'
  ) = 1
  and exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'list_company_invitation_codes'
      and function_entry.prokind = 'f'
      and function_entry.oid = pg_catalog.to_regprocedure(
        'public.list_company_invitation_codes()'
      )
      and function_entry.pronargs = 0
      and function_entry.proargtypes = ''::pg_catalog.oidvector
  )
  and (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'revoke_company_invitation_code'
  ) = 1
  and exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname = 'revoke_company_invitation_code'
      and function_entry.prokind = 'f'
      and function_entry.oid = pg_catalog.to_regprocedure(
        'public.revoke_company_invitation_code(uuid)'
      )
      and function_entry.pronargs = 1
      and function_entry.proargtypes[0] =
        'pg_catalog.uuid'::pg_catalog.regtype
  ),
  'invitation management RPC names must each have exactly one expected typed function'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    join pg_catalog.pg_roles as owner_entry
      on owner_entry.oid = function_entry.proowner
    where namespace_entry.nspname = 'public'
      and function_entry.proname in (
        'create_company_invitation_code',
        'list_company_invitation_codes',
        'revoke_company_invitation_code'
      )
      and (
        not function_entry.prosecdef
        or owner_entry.rolname in ('anon', 'authenticated', 'service_role')
        or function_entry.proconfig is distinct from array['search_path=""']::text[]
        or not pg_catalog.has_function_privilege(
          'authenticated',
          function_entry.oid,
          'EXECUTE'
        )
      )
  )
  and not exists (
    select 1
    from pg_catalog.pg_proc as function_entry
    join pg_catalog.pg_namespace as namespace_entry
      on namespace_entry.oid = function_entry.pronamespace
    where namespace_entry.nspname = 'public'
      and function_entry.proname in (
        'create_company_invitation_code',
        'list_company_invitation_codes',
        'revoke_company_invitation_code'
      )
      and (
        (
          function_entry.proname = 'create_company_invitation_code'
          and function_entry.oid is distinct from pg_catalog.to_regprocedure(
            'public.create_company_invitation_code(integer,integer)'
          )
        )
        or (
          function_entry.proname = 'list_company_invitation_codes'
          and function_entry.oid is distinct from pg_catalog.to_regprocedure(
            'public.list_company_invitation_codes()'
          )
        )
        or (
          function_entry.proname = 'revoke_company_invitation_code'
          and function_entry.oid is distinct from pg_catalog.to_regprocedure(
            'public.revoke_company_invitation_code(uuid)'
          )
        )
      )
      and pg_catalog.has_function_privilege(
        'authenticated',
        function_entry.oid,
        'EXECUTE'
      )
  ),
  'only secure expected invitation management signatures may receive authenticated execute'
);

insert into pg_temp.module1_invitation_management_generated_codes (
  label,
  invitation_id,
  raw_code
)
select 'revoked', invitation_id, invitation_code
from public.create_company_invitation_code(7::integer, 1::integer);

select pg_temp.assert_true(
  (
    select pg_catalog.count(*) = 1
      and pg_catalog.bool_and(raw_code ~ '^[A-F0-9]{6}(-[A-F0-9]{6}){3}$')
      and pg_catalog.bool_and(pg_catalog.char_length(raw_code) = 27)
    from pg_temp.module1_invitation_management_generated_codes
    where label = 'revoked'
  ),
  'admin creation must return one high-entropy grouped invitation code'
);

select pg_temp.assert_true(
  (
    select invitation.assigned_role = 'company_user'
      and invitation.created_by_user_id = auth.uid()
      and invitation.code_hash <> generated.raw_code
      and invitation.code_hash = pg_catalog.encode(
        extensions.digest(
          pg_catalog.convert_to(pg_catalog.btrim(generated.raw_code), 'UTF8'),
          'sha256'
        ),
        'hex'
      )
      and invitation.code_hint = '••••-' || pg_catalog.right(generated.raw_code, 4)
    from public.company_invitation_codes as invitation
    join pg_temp.module1_invitation_management_generated_codes as generated
      on generated.invitation_id = invitation.id
    where generated.label = 'revoked'
  ),
  'creation must store only the canonical SHA-256 hash and a safe code hint'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from public.list_company_invitation_codes() as listing
    where pg_catalog.to_jsonb(listing) ? 'invitation_code'
      or pg_catalog.to_jsonb(listing) ? 'code_hash'
  )
  and pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.list_company_invitation_codes()'::regprocedure
    ),
    'code_hash'
  ) = 0,
  'list RPC must never return raw invitation codes or code hashes'
);

do $module1_invitation_management_bounds$
begin
  begin
    perform public.create_company_invitation_code(0::integer, 1::integer);
    raise exception 'Expected invalid expiry rejection' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform public.create_company_invitation_code(7::integer, 21::integer);
    raise exception 'Expected invalid maximum-use rejection' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;
end;
$module1_invitation_management_bounds$;

do $module1_invitation_management_direct_table_denial$
begin
  begin
    perform 1 from public.company_invitation_codes limit 1;
    raise exception 'Expected direct invitation table read denial' using errcode = 'P0001';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.company_invitation_codes (
      company_id,
      code_hash,
      assigned_role,
      is_active,
      use_count
    )
    values (
      '11000000-0000-4000-8000-000000000001'::uuid,
      pg_catalog.repeat('a', 64),
      'company_user',
      true,
      0
    );
    raise exception 'Expected direct invitation table write denial' using errcode = 'P0001';
  exception
    when insufficient_privilege then null;
  end;
end;
$module1_invitation_management_direct_table_denial$;

-- A company user has no management authority even when its profile shares the
-- same company as the administrator.
reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000002',
  true
);

do $module1_invitation_management_user_denial$
begin
  begin
    perform public.create_company_invitation_code(7::integer, 1::integer);
    raise exception 'Expected company-user create denial' using errcode = 'P0001';
  exception
    when sqlstate '28000' then null;
  end;

  begin
    perform public.list_company_invitation_codes();
    raise exception 'Expected company-user list denial' using errcode = 'P0001';
  exception
    when sqlstate '28000' then null;
  end;

  begin
    perform public.revoke_company_invitation_code(
      '13000000-0000-4000-8000-000000000001'::uuid
    );
    raise exception 'Expected company-user revoke denial' using errcode = 'P0001';
  exception
    when sqlstate '28000' then null;
  end;
end;
$module1_invitation_management_user_denial$;

-- Another company's administrator sees no Company A metadata and cannot
-- revoke an invitation that it does not own.
reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000003',
  true
);

select pg_temp.assert_true(
  not exists (select 1 from public.list_company_invitation_codes()),
  'cross-company administrators must not receive invitation metadata'
);

do $module1_invitation_management_cross_company_revoke$
declare
  v_invitation_id uuid;
begin
  select invitation_id
  into v_invitation_id
  from pg_temp.module1_invitation_management_generated_codes
  where label = 'revoked';

  begin
    perform public.revoke_company_invitation_code(v_invitation_id);
    raise exception 'Expected cross-company revoke denial' using errcode = 'P0001';
  exception
    when sqlstate 'P0002' then null;
  end;
end;
$module1_invitation_management_cross_company_revoke$;

-- The anon API role cannot execute any management RPC.
reset role;
set local role anon;

do $module1_invitation_management_anon_denial$
begin
  begin
    perform public.create_company_invitation_code(7::integer, 1::integer);
    raise exception 'Expected anon create execute denial' using errcode = 'P0001';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.list_company_invitation_codes();
    raise exception 'Expected anon list execute denial' using errcode = 'P0001';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.revoke_company_invitation_code(
      '13000000-0000-4000-8000-000000000001'::uuid
    );
    raise exception 'Expected anon revoke execute denial' using errcode = 'P0001';
  exception
    when insufficient_privilege then null;
  end;
end;
$module1_invitation_management_anon_denial$;

-- Revoke is idempotent and blocks future claims, while a membership claimed
-- before revocation remains assigned to the original company and role.
reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000001',
  true
);

insert into pg_temp.module1_invitation_management_generated_codes (
  label,
  invitation_id,
  raw_code
)
select 'claimed', invitation_id, invitation_code
from public.create_company_invitation_code(7::integer, 1::integer);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000004',
  true
);

do $module1_invitation_management_claim_before_revoke$
declare
  v_raw_code text;
begin
  select raw_code
  into v_raw_code
  from pg_temp.module1_invitation_management_generated_codes
  where label = 'claimed';

  perform public.claim_company_membership('MODULE1INVITEA', v_raw_code);
end;
$module1_invitation_management_claim_before_revoke$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000001',
  true
);

select pg_temp.assert_true(
  public.revoke_company_invitation_code(
    (select invitation_id from pg_temp.module1_invitation_management_generated_codes where label = 'revoked')
  )
  and public.revoke_company_invitation_code(
    (select invitation_id from pg_temp.module1_invitation_management_generated_codes where label = 'revoked')
  ),
  'same-company revoke must be idempotently successful'
);

select pg_temp.assert_true(
  (
    select profile.company_id = '11000000-0000-4000-8000-000000000001'::uuid
      and profile.role = 'company_user'
    from public.profiles as profile
    where profile.user_id = '12000000-0000-4000-8000-000000000004'::uuid
  ),
  'revoking a claimed invitation must not change the existing membership'
);

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000005',
  true
);

do $module1_invitation_management_revoked_claim$
declare
  v_raw_code text;
begin
  select raw_code
  into v_raw_code
  from pg_temp.module1_invitation_management_generated_codes
  where label = 'revoked';

  begin
    perform public.claim_company_membership('MODULE1INVITEA', v_raw_code);
    raise exception 'Expected revoked invitation claim denial' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;
end;
$module1_invitation_management_revoked_claim$;

-- Expired and exhausted invitation checks in the original claim RPC remain
-- active after it is replaced to account for revoked_at.
reset role;
set local role service_role;

insert into public.company_invitation_codes (
  company_id,
  code_hash,
  assigned_role,
  is_active,
  expires_at,
  max_uses,
  use_count,
  code_hint
)
values
  (
    '11000000-0000-4000-8000-000000000001',
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to('MODULE1-EXPIRED-TEST-CODE', 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    'company_user',
    true,
    pg_catalog.now() - interval '1 day',
    1,
    0,
    '••••-TEST'
  ),
  (
    '11000000-0000-4000-8000-000000000001',
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to('MODULE1-LIMITED-TEST-CODE', 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    'company_user',
    true,
    pg_catalog.now() + interval '1 day',
    1,
    1,
    '••••-USED'
  );

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000005',
  true
);

do $module1_invitation_management_expired_claim$
begin
  begin
    perform public.claim_company_membership(
      'MODULE1INVITEA',
      'MODULE1-EXPIRED-TEST-CODE'
    );
    raise exception 'Expected expired invitation claim denial' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;
end;
$module1_invitation_management_expired_claim$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000006',
  true
);

do $module1_invitation_management_limited_claim$
begin
  begin
    perform public.claim_company_membership(
      'MODULE1INVITEA',
      'MODULE1-LIMITED-TEST-CODE'
    );
    raise exception 'Expected exhausted invitation claim denial' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;
end;
$module1_invitation_management_limited_claim$;

-- Seed exactly twenty active unused codes. The admin must be unable to create
-- a twenty-first active code for the same company.
reset role;
set local role service_role;

insert into public.company_invitation_codes (
  company_id,
  code_hash,
  assigned_role,
  is_active,
  expires_at,
  max_uses,
  use_count,
  code_hint
)
select
  '11000000-0000-4000-8000-000000000001'::uuid,
  pg_catalog.lpad(pg_catalog.to_hex(sequence_number), 64, 'a'),
  'company_user',
  true,
  pg_catalog.now() + interval '1 day',
  1,
  0,
  '••••-CAP'
from pg_catalog.generate_series(1, 20) as sequence_number;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '12000000-0000-4000-8000-000000000001',
  true
);

do $module1_invitation_management_active_cap$
begin
  begin
    perform public.create_company_invitation_code(7::integer, 1::integer);
    raise exception 'Expected active invitation cap denial' using errcode = 'P0001';
  exception
    when sqlstate '22023' then null;
  end;
end;
$module1_invitation_management_active_cap$;

select pg_temp.assert_true(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'public.claim_company_membership(text,text)'::regprocedure
      )
    ),
    'for update'
  ) > 0
  and pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.claim_company_membership(text,text)'::regprocedure
    ),
    'revoked_at'
  ) > 0,
  'claim RPC must retain row locking and revoked-code handling'
);

reset role;
rollback;
