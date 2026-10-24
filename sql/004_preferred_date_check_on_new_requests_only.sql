-- ============================================================================
-- 004_preferred_date_check_on_new_requests_only.sql   *** DRAFT - NOT RUN. Awaiting approval. ***
--
-- Why: the table rule "requests_preferred_date_not_past" (preferred_date >=
-- current_date) is re-checked by Postgres on EVERY update of a row, not only when
-- preferred_date changes. Once a request's preferred date has passed, staff can no
-- longer change its status (mark reviewed, assign a date, decline, complete...).
-- Proven 2026-10-24: a status-only update of AG-2026-0003 (preferred 2026-10-23)
-- was refused with this constraint, inside a rolled-back test.
--
-- Fix: the rule is only meant for NEW requests ("don't ask for a visit in the
-- past"). So remove it from the table and enforce it where requests are created:
--   1. submit_request()  (the public path)
--   2. the staff INSERT policy  (the staff path, step 8)
-- Behaviour for new requests is unchanged: a past date is still refused.
-- One transaction.
-- ============================================================================
begin;

alter table public.requests drop constraint requests_preferred_date_not_past;

-- 1. public path: past or missing date -> the same generic 'invalid_request' error
create or replace function public.submit_request(
  p_first_name      text,
  p_last_name       text,
  p_phone           text,
  p_email           text,
  p_visitor_type    text,
  p_visitor_detail  text,
  p_target_official text,
  p_purpose         text,
  p_preferred_date  date
)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_ref text;
begin
  if char_length(btrim(coalesce(p_first_name, ''))) not between 1 and 100
     or char_length(btrim(coalesce(p_last_name, ''))) not between 1 and 100
     or char_length(coalesce(p_phone, '')) not between 8 and 15
     or (p_visitor_detail is not null and char_length(p_visitor_detail) > 200)
     or p_email is null
     or char_length(p_email) > 254
     or p_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or p_target_official is null
     or p_target_official <> all (array['gov','sg','sp','ig','daaj','daesc','dbr','dpoa'])
     or p_preferred_date is null
     or p_preferred_date < current_date
  then
    raise exception 'invalid_request' using errcode = '22023';
  end if;

  insert into public.requests
    (first_name, last_name, phone, email, visitor_type, visitor_detail,
     target_official, purpose, preferred_date)
  values
    (btrim(p_first_name), btrim(p_last_name), p_phone, p_email, p_visitor_type, p_visitor_detail,
     p_target_official, p_purpose, p_preferred_date)
  returning reference_number into v_ref;

  return v_ref;
end;
$function$;
-- (EXECUTE rights on submit_request are unchanged by CREATE OR REPLACE.)

-- 2. staff path: same policy as in 003, plus the date rule (still exactly one INSERT policy)
alter policy "Staff can insert requests" on public.requests
  with check (
        private.is_active_staff(auth.uid())
    and status = 'pending'
    and delegate_to is null
    and reject_reason is null
    and flagged_for_reschedule = false
    and flagged_at is null
    and created_at = now()
    and updated_at = now()
    and preferred_date >= current_date
    and char_length(btrim(first_name)) between 1 and 100
    and char_length(btrim(last_name))  between 1 and 100
    and char_length(phone) between 8 and 15
    and (visitor_detail is null or char_length(visitor_detail) <= 200)
    and email is not null
    and char_length(email) <= 254
    and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and target_official in ('gov','sg','sp','ig','daaj','daesc','dbr','dpoa')
  );

commit;

-- ----------------------------------------------------------------------------
-- VERIFY afterwards (read-only except the rolled-back test):
--  a) constraint gone:
--     select conname from pg_constraint where conrelid='public.requests'::regclass and conname like '%preferred_date%';   -- expect 0 rows
--  b) a status update on a PAST-dated request is now accepted (rolled back):
--     do $$ begin
--       update public.requests set status='reviewed', preferred_date = preferred_date where reference_number='AG-2026-0003';
--       raise exception 'ROLLED BACK - update was accepted';
--     end $$;
--     (to test truly past-dated: temporarily nothing to do - the rule no longer exists)
--  c) public path still refuses a past date:  bash sql/003_verify.sh   (B6 must still be refused)
--  d) one INSERT policy per table:  see 001_verify.sql check A
-- ----------------------------------------------------------------------------
