-- ============================================================================
-- 006_staff_cap_6.sql                    *** APPLIED 2026-11-21 (Parts A and B), run by Angel in the SQL Editor. DO NOT RE-RUN. ***
--
-- Raise the staff cap from 3 to 6.  Two independent parts:
--   PART A  the cap itself (3 -> 6).  Behaviour otherwise identical to the live function.
--   PART B  OPTIONAL. Count only ACTIVE staff when adding someone. Approve or drop separately.
--
-- Live behaviour today (read from the database 2026-11-21):
--   INSERT into staff         counts ALL rows (active or not); refuses at >= 3
--   UPDATE inactive -> active counts ACTIVE rows;              refuses at >= 3
--   any other update          not checked
-- ============================================================================


-- ============================================================================
-- PART A - the cap (one transaction)
-- Order: (1) create the new function  (2) repoint the trigger  (3) drop the old function
-- No CASCADE anywhere: if anything still depended on the old function, step 3 fails
-- and the whole transaction rolls back, leaving everything as it is today.
-- ============================================================================
begin;

-- A1. the new function. The cap is written in ONE place (max_staff).
create function public.enforce_staff_max()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'        -- pinned, like the other functions
as $function$
declare
  max_staff constant integer := 6;
  current_count integer;
begin
  if tg_op = 'INSERT' then
    select count(*) into current_count from public.staff;
    if current_count >= max_staff then
      raise exception 'Maximum of % staff accounts allowed.', max_staff;
    end if;
  end if;

  if tg_op = 'UPDATE' and new.is_active = true and old.is_active = false then
    select count(*) into current_count from public.staff where is_active = true;
    if current_count >= max_staff then
      raise exception 'Maximum of % active staff accounts allowed.', max_staff;
    end if;
  end if;

  return new;
end;
$function$;

-- A2. no execute rights for anyone through the API (triggers fire without them)
revoke execute on function public.enforce_staff_max() from public, anon, authenticated;

-- A3. repoint the trigger (same name, same timing, new function)
drop trigger trg_staff_limit on public.staff;
create trigger trg_staff_limit
  before insert or update on public.staff
  for each row execute function public.enforce_staff_max();

-- A4. last: remove the old function (plain DROP, no CASCADE)
drop function public.enforce_three_staff_max();

commit;


-- ============================================================================
-- PART B - OPTIONAL: "count only active staff when adding someone"   (separate transaction)
-- Effect: a DEACTIVATED person no longer uses up a slot when someone new is added, so
-- the office does not have to delete the row to make room. The cap then means
-- "at most 6 ACTIVE staff", on insert as well as on reactivation.
-- Side effects to be aware of:
--   * inactive rows can pile up in the staff table (they cannot sign in to the data, but
--     their login accounts still exist in Auth until deleted there);
--   * inserting a person who is created as INACTIVE is not limited (only active ones count).
-- If you drop Part B, nothing below is run and Part A behaves as the live function does today.
-- ============================================================================
begin;

create or replace function public.enforce_staff_max()
returns trigger
language plpgsql
set search_path to 'public', 'pg_catalog'
as $function$
declare
  max_staff constant integer := 6;
  current_count integer;
begin
  if tg_op = 'INSERT' and new.is_active = true then
    select count(*) into current_count from public.staff where is_active = true;
    if current_count >= max_staff then
      raise exception 'Maximum of % active staff accounts allowed.', max_staff;
    end if;
  end if;

  if tg_op = 'UPDATE' and new.is_active = true and old.is_active = false then
    select count(*) into current_count from public.staff where is_active = true;
    if current_count >= max_staff then
      raise exception 'Maximum of % active staff accounts allowed.', max_staff;
    end if;
  end if;

  return new;
end;
$function$;
-- (CREATE OR REPLACE keeps the revoked execute rights and the trigger as they are.)

commit;


-- ============================================================================
-- CHECKS AFTER RUNNING  (all read-only, except the optional rolled-back test below)
--
-- 1. Exactly one enabled trigger on staff, pointing at the new function:
--      select count(*) as triggers, count(*) filter (where tgenabled = 'O') as enabled,
--             string_agg(pg_get_triggerdef(oid), ' | ') as definition
--      from pg_trigger where tgrelid = 'public.staff'::regclass and not tgisinternal;
--
-- 2. The old function is gone:
--      select count(*) as old_function_left from pg_proc
--      where pronamespace = 'public'::regnamespace and proname = 'enforce_three_staff_max';
--
-- 3. The new function text contains the cap of 6, a pinned search path and no public execute:
--      select pg_get_functiondef(oid) like '%max_staff constant integer := 6%' as cap_is_6,
--             proconfig as search_path_setting,
--             proacl::text as execute_rights
--      from pg_proc where pronamespace = 'public'::regnamespace and proname = 'enforce_staff_max';
--
-- 4. Nothing else moved (run before AND after any test):
--      select (select count(*) from public.staff) as staff_rows,
--             (select count(*) from public.staff where is_active) as active_staff,
--             (select count(*) from auth.users) as login_accounts;          -- expect 3 / 3 / 3
--
-- 5. BEHAVIOUR TEST (only if it can be guaranteed to leave no trace - see note).
--    It adds up to 4 throwaway login+staff entries inside ONE statement whose last action
--    is an unconditional error, so everything it did is undone. Check 4 is run again afterwards
--    and must still say 3 / 3 / 3.
--      Part A alone: inserts #4, #5, #6 accepted, #7 refused "Maximum of 6 staff accounts allowed."
--
--      do $$
--      declare r text := ''; i int; uid uuid;
--      begin
--        for i in 1..4 loop
--          uid := gen_random_uuid();
--          insert into auth.users (id, email, aud, role)
--            values (uid, 'zz-cap-test-' || i || '@example.invalid', 'authenticated', 'authenticated');
--          begin
--            insert into public.staff (auth_user_id, full_name, email)
--              values (uid, 'ZZ cap test ' || i, 'zz-cap-test-' || i || '@example.invalid');
--            r := r || 'insert #' || (3 + i) || ': accepted; ';
--          exception when others then
--            r := r || 'insert #' || (3 + i) || ': REFUSED (' || sqlerrm || '); ';
--          end;
--        end loop;
--        raise exception 'ROLLED BACK, nothing saved: %', r;
--      end $$;
--
--    If Part B is approved, the same style of test is run for it: add three (6 active), #7 refused,
--    deactivate one of the THROWAWAY rows, then #7 is accepted.
--    Note: if the SQL tool is not allowed to create the throwaway login records, this test
--    simply fails at its first line, changes nothing, and is reported as SKIPPED.
-- ============================================================================
