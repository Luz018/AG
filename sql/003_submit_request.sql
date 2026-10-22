-- ============================================================================
-- 003_submit_request.sql          *** DRAFT - NOT RUN. Awaiting approval. ***
--
-- Why: the public has (rightly) no permission to READ the requests table, so a
-- normal "insert and give me the row back" is refused and the form could not
-- show the reference number. Fix (Option A): a function that inserts the
-- request and returns ONLY the reference number, and becomes the ONLY way for
-- the public to create a request.
--
-- Everything is one transaction.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- 1. The function. SECURITY DEFINER = it runs with the owner's rights, so it
--    can insert without the caller being able to read anything. Because it
--    bypasses the table's RLS policy, it must do ALL the checking itself, so the
--    rules below are the same ones the policy used. The table's own CHECK
--    constraints still apply on top (purpose <= 600 chars / 50 words, date not
--    in the past, visitor_type values, status values).
--
--    Callers can only pass the 9 form fields. status, reference number, dates and
--    every staff field are set by the database (status defaults to 'pending',
--    the trigger always generates the AG-YYYY-NNNN number), so there is nothing
--    to forge. Any failure raises one generic error ('invalid_request') that
--    reveals nothing.
-- ----------------------------------------------------------------------------
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

-- the public page (anon) and a logged-in staff member using the public page
revoke execute on function public.submit_request(text,text,text,text,text,text,text,text,date) from public;
grant  execute on function public.submit_request(text,text,text,text,text,text,text,text,date) to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 2. Remove the public's direct insert right on the table.
--    After this, "anon" cannot INSERT into requests at all: the function above
--    is the only way in.
-- ----------------------------------------------------------------------------
revoke insert on public.requests from anon;

-- Defense in depth: anon also held SELECT and UPDATE on requests. Row-level
-- security already blocks them (verified), but remove the grants themselves.
-- (The public lookup/reschedule/duplicate functions are SECURITY DEFINER and
-- do not need the caller to have table rights.)
revoke select, update on public.requests from anon;


-- ----------------------------------------------------------------------------
-- 3. The one INSERT policy still exists (it must stay exactly one) but is now
--    narrowed to ACTIVE STAFF only. Without this, any logged-in account (not
--    only staff) could insert directly and skip the function. The citizen
--    conditions stay for now; Step 6 (staff register a phone-only request)
--    will edit THIS policy to allow staff entries without an email.
-- ----------------------------------------------------------------------------
alter policy "Public can insert requests" on public.requests
  to authenticated
  with check (
        private.is_active_staff(auth.uid())
    and status = 'pending'
    and delegate_to is null
    and reject_reason is null
    and flagged_for_reschedule = false
    and flagged_at is null
    and created_at = now()
    and updated_at = now()
    and char_length(btrim(first_name)) between 1 and 100
    and char_length(btrim(last_name))  between 1 and 100
    and char_length(phone) between 8 and 15
    and (visitor_detail is null or char_length(visitor_detail) <= 200)
    and email is not null
    and char_length(email) <= 254
    and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and target_official in ('gov','sg','sp','ig','daaj','daesc','dbr','dpoa')
  );

alter policy "Public can insert requests" on public.requests rename to "Staff can insert requests";

commit;
