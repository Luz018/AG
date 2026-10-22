-- ============================================================================
-- 001_security_fixes.sql          *** DRAFT - NOT RUN. Awaiting approval. ***
--
-- Written 2026-10-22 against the live schema as read that day (pg_policies,
-- pg_constraint, pg_proc, pg_trigger). Everything is ONE transaction: if any
-- statement fails, nothing is applied.
--
--   Part 1  Replace the public INSERT policy on requests (the hole)
--   Part 2  New request statuses (+ assigned_date column)
--   Part 3  Cleanup: total_staff overlap, hide helper functions, pin search_path
--   Part 4  Attempt limiting on lookup_request / flag_reschedule_request
--
-- After running, run 001_verify.sql and 001_verify.sh (see those files).
--
-- NOTE 2026-10-22: this file WAS applied. It contains one mistake ("request_year
-- is null" in the insert policy; that column is generated). Fixed live by
-- 002_fix_insert_policy_request_year.sql. Do not re-run this file.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- PRE-CHECK (read-only). Expect: only 'pending' / 'approved' / 'rejected'
-- appear. If 'delegated' or 'rescheduled' appear, Part 2 will fail and the
-- whole transaction rolls back harmlessly.
-- ----------------------------------------------------------------------------
select status, count(*) from public.requests group by status;


-- ============================================================================
-- PART 1 - the public INSERT policy on public.requests
-- ----------------------------------------------------------------------------
-- Today: "Public can insert requests", WITH CHECK (true)  -> anyone with the
-- public key can insert status='approved', fake reject reasons, etc.
--
-- New: ONE policy, for anon AND authenticated (a staff member whose browser is
-- still logged in can also use the public form). Every staff-only field must
-- be at its default. Step 6 (staff register a phone-only request) will EDIT
-- THIS SAME POLICY, never add a second INSERT policy (bug 3: policies are OR'd).
--
-- Note: WITH CHECK is evaluated AFTER the BEFORE-INSERT trigger, so
-- reference_number can't be tested as "null" here. Instead the trigger is
-- changed (below) to ALWAYS generate the number, ignoring anything supplied.
-- created_at/updated_at are pinned to now() so dates can't be backdated to
-- dodge the 7-day duplicate check.
-- ----------------------------------------------------------------------------
drop policy "Public can insert requests" on public.requests;

create policy "Public can insert requests"
  on public.requests
  for insert
  to anon, authenticated
  with check (
        status = 'pending'
    and delegate_to is null
    and reject_reason is null
    and flagged_for_reschedule = false
    and flagged_at is null
    and request_year is null
    and created_at = now()
    and updated_at = now()
    -- required, sensible lengths
    and char_length(btrim(first_name)) between 1 and 100
    and char_length(btrim(last_name))  between 1 and 100
    and char_length(phone) between 8 and 15
    and (visitor_detail is null or char_length(visitor_detail) <= 200)
    -- email required for citizen self-submission (Step 6 will add the
    -- staff phone-only exception inside this same policy)
    and email is not null
    and char_length(email) <= 254
    and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    -- only offices that exist on the form
    and target_official in ('gov','sg','sp','ig','daaj','daesc','dbr','dpoa')
  );
-- (purpose length/word limit, preferred_date >= today, visitor_type values
--  are already enforced by existing table CHECK constraints.)

-- Make the reference number impossible to forge: always generated.
create or replace function public.set_reference_number()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  next_val integer;
begin
  next_val := nextval('public.request_ref_seq');
  new.reference_number := 'AG-' || extract(year from now())::text
                           || '-' || lpad(next_val::text, 4, '0');
  return new;
end;
$function$;


-- ============================================================================
-- PART 2 - statuses for the section-5 flow
-- ----------------------------------------------------------------------------
-- Stored value        Shown to people as
--   pending             Submitted               (what citizens create)
--   reviewed            Reviewed by staff
--   awaiting_decision   Awaiting the governor's decision
--   date_assigned       Date assigned
--   completed           Completed
--   declined            Declined
-- 'approved' and 'rejected' are KEPT TEMPORARILY because the current
-- staff.html still writes them; a later migration (after staff.html is
-- updated and the data converted) removes them. 'delegated' and
-- 'rescheduled' are dropped for requests (delegate feature was removed;
-- reschedule is recorded in the history table, which is unchanged).
-- ----------------------------------------------------------------------------
alter table public.requests drop constraint requests_status_check;

alter table public.requests add constraint requests_status_check
  check (status = any (array[
    'pending','reviewed','awaiting_decision','date_assigned','completed','declined',
    'approved','rejected'      -- legacy, to be removed in a later migration
  ]));

-- the date the governor assigns (printed summary / staff record it)
alter table public.requests add column assigned_date date;

alter table public.requests add constraint requests_assigned_date_required
  check (status not in ('date_assigned') or assigned_date is not null);


-- ============================================================================
-- PART 3 - cleanup
-- ----------------------------------------------------------------------------
-- 3a. total_staff has a "deny all" policy AND a "readable" policy; they are
--     OR'd, so the deny is partly cancelled. Nothing in the site uses this
--     table. Keep only the deny-all policy.
drop policy "Authenticated users can read total_staff" on public.total_staff;

-- 3b. is_active_staff / is_active_admin are only meant for the policies, but
--     they are callable from outside as /rest/v1/rpc/... Move them to a
--     schema the API does not expose. Existing policies follow automatically
--     (they point at the function itself, not its name). The roles keep
--     USAGE on the schema + EXECUTE on the functions, because policy
--     expressions run with the caller's rights.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

alter function public.is_active_staff(uuid) set schema private;
alter function public.is_active_admin(uuid) set schema private;

-- 3c. trigger-only function: nobody should call it directly. (Triggers fire
--     without the caller needing EXECUTE.)
revoke execute on function public.set_reference_number() from public, anon, authenticated;

-- 3d. pin search_path on the three functions flagged by Supabase's advisor
alter function public.enforce_three_staff_max() set search_path = public, pg_catalog;
alter function public.set_updated_at()          set search_path = public, pg_catalog;
alter function public.keepalive()               set search_path = public, pg_catalog;
-- keepalive stays callable by anon: the GitHub keep-alive job uses it.


-- ============================================================================
-- PART 4 - attempt limiting for the two "reference + phone" functions
-- ----------------------------------------------------------------------------
-- DESIGN CHOICE (please review): the database can't reliably see the caller's
-- IP address, so limits are per reference number and overall:
--   * 5 failed tries on the same reference number in 15 min -> that reference
--     answers "no match" for the rest of the 15 min
--   * 60 failed tries in total in 10 min -> everything answers "no match"
--     for the rest of the 10 min
-- A locked or wrong lookup looks IDENTICAL ("no match found"), so an attacker
-- learns nothing. Cost: a real person who mistypes 5 times must wait 15 min,
-- and a determined attacker could briefly lock lookups for everyone (the form
-- itself keeps working; only "check my request" is affected).
-- Alternative if you prefer: a CAPTCHA (e.g. Cloudflare Turnstile) in front,
-- which needs an extra account. Not included here.
-- ----------------------------------------------------------------------------
create table private.lookup_attempts (
  id           bigint generated always as identity primary key,
  reference    text        not null,
  attempted_at timestamptz not null default now(),
  succeeded    boolean     not null
);
create index lookup_attempts_ref_idx on private.lookup_attempts (reference, attempted_at);
alter table private.lookup_attempts enable row level security;   -- no policies = no access
revoke all on private.lookup_attempts from public, anon, authenticated;

create or replace function public.lookup_request(p_reference text, p_phone text)
returns table(status text, target_official text, preferred_date date, flagged_for_reschedule boolean)
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_ref text := left(btrim(coalesce(p_reference, '')), 30);
  v_ref_fails int;
  v_all_fails int;
begin
  delete from private.lookup_attempts where attempted_at < now() - interval '1 day';

  select count(*) into v_ref_fails from private.lookup_attempts a
   where a.reference = v_ref and not a.succeeded and a.attempted_at > now() - interval '15 minutes';
  select count(*) into v_all_fails from private.lookup_attempts a
   where not a.succeeded and a.attempted_at > now() - interval '10 minutes';
  if v_ref_fails >= 5 or v_all_fails >= 60 then
    return;                                   -- same as "no match"
  end if;

  return query
    select r.status, r.target_official, r.preferred_date, r.flagged_for_reschedule
      from public.requests r
     where r.reference_number = v_ref and r.phone = p_phone
     limit 1;

  insert into private.lookup_attempts (reference, succeeded) values (v_ref, found);
end;
$function$;

create or replace function public.flag_reschedule_request(p_reference text, p_phone text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_ref text := left(btrim(coalesce(p_reference, '')), 30);
  v_ref_fails int;
  v_all_fails int;
  rows_updated integer;
begin
  select count(*) into v_ref_fails from private.lookup_attempts a
   where a.reference = v_ref and not a.succeeded and a.attempted_at > now() - interval '15 minutes';
  select count(*) into v_all_fails from private.lookup_attempts a
   where not a.succeeded and a.attempted_at > now() - interval '10 minutes';
  if v_ref_fails >= 5 or v_all_fails >= 60 then
    return false;
  end if;

  update public.requests r
     set flagged_for_reschedule = true, flagged_at = now()
   where r.reference_number = v_ref
     and r.phone = p_phone
     and r.status in ('pending', 'reviewed', 'awaiting_decision', 'date_assigned', 'approved');
  get diagnostics rows_updated = row_count;

  insert into private.lookup_attempts (reference, succeeded) values (v_ref, rows_updated > 0);
  return rows_updated > 0;
end;
$function$;
-- (Both keep their existing EXECUTE rights for anon: the public page needs them.
--  has_recent_duplicate is unchanged; it only returns yes/no. Accepted risk.)

commit;
