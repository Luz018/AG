-- ============================================================================
-- 002_fix_insert_policy_request_year.sql     *** DRAFT - NOT RUN. Awaiting approval. ***
--
-- Why: 001 put "request_year is null" in the public INSERT policy. But
-- request_year is a GENERATED column (= year of preferred_date), so it is never
-- null on a real row. Result: the policy refused EVERY citizen request, valid or
-- not. Found 2026-10-22 by checking each condition against a rolled-back row.
-- (A generated column cannot be written by a client anyway, so the check was
-- never needed.)
--
-- ALTER POLICY changes the existing policy in place: there is never a moment
-- with zero or two INSERT policies. Only the one line is removed; everything
-- else is identical to 001.
-- ============================================================================
begin;

alter policy "Public can insert requests" on public.requests
  with check (
        status = 'pending'
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

commit;
