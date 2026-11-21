-- ============================================================================
-- 005_staff_register_requests.sql        *** DRAFT - NOT RUN. Awaiting approval. ***
--
-- Step 8: a staff member registers a request on someone's behalf (phone call or
-- visit). Only a phone number is required; WhatsApp becomes the contact method
-- for any request without an email. One transaction.
--
-- What changes:
--   1. New column requests.registered_by  (the staff member's login id; NULL for
--      requests the citizen submitted themselves).
--   2. The ONE existing INSERT policy "Staff can insert requests" is edited (no
--      second policy is added):
--        - every staff entry must carry registered_by = the logged-in staff member
--          (so a staff insert can never pass as a citizen's own submission, and the
--          office can see who entered it)
--        - email becomes OPTIONAL there; if given it must still look like an email
--        - everything else is exactly as in 004 (status 'pending', staff-only fields
--          empty, dates pinned, lengths, office list, preferred date not in the past)
--
-- What does NOT change:
--   * submit_request() (the public path) still REQUIRES an email and never sets
--     registered_by.
--   * The public (anon) key still has no insert/select/update on requests.
-- ============================================================================
begin;

alter table public.requests
  add column registered_by uuid references auth.users (id) on delete set null;

comment on column public.requests.registered_by is
  'Staff member (auth user id) who registered this request on a citizen''s behalf; NULL = submitted by the citizen online.';

alter policy "Staff can insert requests" on public.requests
  with check (
        private.is_active_staff(auth.uid())
    and registered_by = auth.uid()
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
    and (email is null
         or (char_length(email) <= 254
             and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'))
    and target_official in ('gov','sg','sp','ig','daaj','daesc','dbr','dpoa')
  );

commit;

-- ----------------------------------------------------------------------------
-- VERIFY afterwards
--  a) one INSERT policy on requests, and it mentions registered_by:
--       select policyname, with_check like '%registered_by = auth.uid()%' as marks_staff
--       from pg_policies where schemaname='public' and tablename='requests' and cmd='INSERT';
--  b) column exists, nullable, FK to auth.users:
--       select column_name, is_nullable from information_schema.columns
--       where table_schema='public' and table_name='requests' and column_name='registered_by';
--  c) public path unchanged - run:  bash sql/003_verify.sh   (all direct inserts refused, B1-B9 as before;
--     it creates one more ZZTEST row)
--  d) the staff path itself can only be tested as a logged-in staff member (SQL run from here
--     cannot act as one), so: the staff form, used by Angel, with (1) a phone-only request,
--     (2) a request with an email, (3) a past date -> refused, then check in the staff list.
-- ----------------------------------------------------------------------------
