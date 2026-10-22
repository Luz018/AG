-- 001_verify.sql  -  READ-ONLY checks to run AFTER 001_security_fixes.sql.
-- Nothing here changes data.

-- A. Exactly one policy per (table, command)?  Expect: n = 1 on every row.
select tablename, cmd, count(*) as n, string_agg(policyname, ' | ') as policies
from pg_policies where schemaname = 'public'
group by tablename, cmd order by tablename, cmd;

-- B. The new insert policy text. Expect with_check to be the long condition,
--    NOT 'true', and roles = {anon,authenticated}.
select policyname, roles, with_check from pg_policies
where schemaname = 'public' and tablename = 'requests' and cmd = 'INSERT';

-- C. RLS still on everywhere? Expect all true.
select tablename, rowsecurity from pg_tables where schemaname = 'public';

-- D. Status rule + new column rule are present.
select conname, pg_get_constraintdef(oid) from pg_constraint
where conrelid = 'public.requests'::regclass
  and conname in ('requests_status_check', 'requests_assigned_date_required');

-- E. Helper functions no longer reachable through the API schema.
--    Expect is_active_staff / is_active_admin in schema 'private', not 'public'.
select n.nspname as schema, p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where p.proname in ('is_active_staff','is_active_admin','set_reference_number',
                    'lookup_request','flag_reschedule_request');

-- F. Policies still recognise staff after the move (run as the SQL-editor owner):
--    expect 3.
select count(*) as staff_rows from public.staff;

-- G. After the live tests (001_verify.sh): exactly ONE row named ZZTEST,
--    status 'pending', reference like 'AG-2026-%' (NOT 'FAKE-1'), nothing forged.
select reference_number, status, first_name, email, created_at
from public.requests where first_name like 'ZZTEST%';
