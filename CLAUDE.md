# AudienceGov: Project Brief for Claude Code

First session not yet run. Next action: Section 13 (audit + propose plan, then stop).

## 1. What we're building

A bilingual (French/English) website for the Governor's Office of the
South Region, Ebolowa, Cameroon. It informs citizens about the office and
its services, and lets them submit appointment requests that staff review
and the governor approves.

**Why:** many people don't know what the office does, and some travel
long distances only to find the governor unavailable. The site makes
services known and lets people request a visit before travelling. This
is the actual problem the project exists to solve — weigh every proposed
feature against whether it serves this, not against whether it's a nice
addition.

**Builder:** Angel, a final-year translation student with no coding
background, building with AI assistance. Explain what you're doing in
plain language, define any term you introduce, and never assume she
knows the command line.

**Launch decision:** the Governor decides. Until he approves, the site
lives on a private test URL only.

## 2. Existing work

An earlier version exists (Supabase backend, GitHub Pages front end,
originally a meeting-request app called AudienceGov). Its UI is a bare
prototype that only shows which buttons work. It is **not** presentable
and must be redesigned (see section 8).

**Do not rebuild blindly.** First audit what exists, report what can be
reused and what must change, and wait for approval before deleting
anything. **Read section 2.1 before doing this audit** — several things
listed as "existing" below are already built, tested live in a browser,
and should not be treated as prototype-quality guesses.

## 2.1 What's already confirmed working (tested live, not just written)

- Public form inserts into a `requests` table; a staff page reads and
  updates it.
- Supabase Auth login, with session persistence: the page checks
  `supabaseClient.auth.getSession()` on load before showing the login
  screen, so a previously-logged-in device skips straight to the
  dashboard. Verified safe — a device with no prior session is still
  correctly challenged (tested via a private browser window and a phone
  that had never logged in).
- RLS verified directly by querying `pg_policies` (never assumed from a
  schema file) on `requests`, `history`, `staff`. Exactly one INSERT
  policy on `requests`, requiring `status = 'pending'` and empty
  staff-only fields.
- A staff-count-limit trigger, active and tested.
- A scheduled GitHub Actions keep-alive (twice weekly) confirmed running,
  so the free Supabase plan doesn't pause from inactivity.
- A "delegate to another official" feature was built, then **deliberately
  removed** — offices are physically close together, so a misrouted
  request is handled by staff walking it over or calling, not a digital
  handoff. Do not reintroduce a delegate button, modal, or related
  database logic unless the project owner specifically asks for it back.
- Database-level hardening, all run successfully against the live
  database:
  - A SECURITY DEFINER function to warn about a recent duplicate request
    (same phone + same official within 7 days, counting only
    pending/approved) — returns a boolean only, no data exposed.
  - A `preferred_date >= current_date` CHECK constraint.
  - A purpose-length CHECK: ≤600 characters AND ≤50 words, enforced in
    the database, not only the browser.
  - An auto-generated reference number on insert (format `AG-YYYY-NNNN`),
    shown on the public success screen in both languages. Confirmed
    working.
  - A reschedule/cancel self-service path: a citizen can look up their
    request status and flag "I can't make it" using their reference
    number plus phone number together, with no login required.
- A WhatsApp integration, confirmed as the **free, manual** kind only: a
  button opens a chat with a prefilled message for staff to review and
  send themselves. The paid WhatsApp Business API was evaluated and
  explicitly declined for cost. This matches section 5's instruction
  below — do not build automated WhatsApp sending.

### Known bugs, found and fixed — do not reintroduce these patterns

Each of these was a real, live bug found only by testing in an actual
browser, not by reading the code. **This is the core lesson from building
the earlier version: code that looks correct and passes a syntax check
can still be broken at runtime. Test every claim live before reporting
something as done.**

1. A public INSERT policy using `WITH CHECK (true)` allowed anyone with
   the (intentionally public) anon key to insert a request already
   marked `approved`. Every public INSERT policy must constrain
   `status`, and must null out any staff-only field (decision fields,
   assigned dates, etc.).
2. Building an `onclick="..."` attribute by concatenating
   `JSON.stringify(someId)` into a double-quoted HTML attribute breaks
   it — `JSON.stringify` produces double quotes, which collide with the
   attribute's own double quotes and truncate it, producing invalid JS
   silently. **Never mix `JSON.stringify()` output into a double-quoted
   HTML attribute.**
3. Postgres combines multiple RLS policies for the same (table, command)
   pair with **OR, not AND**. A second, looser policy added later can
   silently reopen a hole a stricter one already closed, with no error.
   **After any RLS change, query `pg_policies` directly and confirm
   exactly one policy per (table, command) pair.** For INSERT policies,
   check the `with_check` column specifically — `qual` does not show it.
4. An AI-driven "find every vulnerability" audit pass once silently
   altered the live schema (added an unexplained column and a view)
   while producing its report. **A request to audit for security issues
   is a request for a report. Any fix must be presented for approval
   before being run against the live database — this applies doubly to
   anything that touches the schema.**
5. Removing a variable's old initialization (an old hardcoded sample-data
   array) without replacing it with a proper empty declaration caused
   every downstream function referencing it to throw
   `ReferenceError`, and the dashboard silently showed zero data with no
   obvious cause on screen. **When removing code that both declared and
   initialized something, check what else still depends on the bare
   declaration existing.**
6. A coding agent process crashed with an out-of-memory error when asked
   to make two separate UI changes in one combined instruction; splitting
   it into two smaller, sequential edits succeeded cleanly. **Keep
   instructions to one self-contained change at a time** on this
   codebase and this class of low-RAM dev machine (see section 9).

## 3. Reference material

Angel will put the text of the decree on the powers of heads of
administrative units and the organization of their services in `/docs/`.
**Confirmed: Décret n° 2008/377 du 12 novembre 2008**, "fixant les
attributions des chefs de circonscriptions administratives et portant
organisation et fonctionnement de leurs services" — verified against the
Journal Officiel and the Présidence de la République's own published
citations, independently of Angel's own check. (It replaced an earlier
1978 decree on the same subject; the correct number is 2008/377, not
"378/2008" as first recalled.)

Use it to understand the governor's role, the Secretariat General and the
vocabulary of the services, so the site uses correct terms. **Do not
invent facts beyond it, and do not copy its text onto the site without
Angel's approval.**

## 4. Pages (all in one release, no v2)

1. **Home:** welcome, what the office does, a clear button to request an
   appointment.
2. **About the region:** history of the South Region.
3. **The Governor's Office:** role, services offered, people in charge.
   Keep ranks and hierarchy low-key (sensitive topic): names and roles,
   no emphasis on power.
4. **News and events:** posted by the office's communications unit
   through a simple staff form (title, text, one photo with **required
   alt text**, optional link). **Videos are embedded links
   (YouTube/Facebook), never uploaded** — a few minutes of raw video is
   tens to hundreds of MB, which is painful to upload over weak
   connections and costs money to host and serve directly, whereas
   YouTube/Facebook compress it, adapt quality to the viewer's
   connection, and host it free. Embeds load only on click, to save
   data, and any embedded video needs captions or a transcript link
   (see section 6).
5. **Request an appointment:** the most important page.
6. **Contact and directions:** address, hours, email, WhatsApp link.

Everything is bilingual with a visible language switch. Pages are
printable (clean print stylesheet).

**Placeholder content rule:** the history and people text will initially
be drafts sourced from the internet and **not verified** — neither Angel
nor Claude Code can confirm their accuracy from outside the office. Every
such block must show a visible banner: "DRAFT: to be verified by the
office". Do not state unverified claims as fact, and do not make the
site public until the office has replaced or confirmed them.

## 5. Request flow (core feature, build first)

**Citizen side:** simple form: name, email, phone/WhatsApp, reason for
visit, preferred period, optional short description. Validate the email
format, and ask for it twice or show it back clearly (typos mean lost
requests). On submit, show a confirmation with a **reference number**.
No account required.

**Email requirement, with an exception:** email is required when a
citizen submits their own request online, since it's the primary
confirmation channel. But do not let a missing email silently exclude
people — some citizens, especially older or rural ones, have no email
address at all, and this app exists specifically to serve people who
have the hardest time reaching the office. Build a **staff-side path**
where a staff member registers a request on someone's behalf (taken by
phone call or in person), where only a phone number is required and
WhatsApp becomes that request's primary contact method instead of email.

**Staff side:** login-protected view (3 to 4 staff expected, though the
project may launch with just one real account — see section 2.1 on how
the current simplified version is structured) listing requests with
status. Staff can open a request, change its status, and print it.

**Status flow:** Submitted, Reviewed by staff, Awaiting the governor's
decision, Date assigned, Completed (or Declined).

**Printable summary:** one A4 page per request: reference number,
requester details, reason, preferred period, status, and blank space for
the governor's decision and assigned date. Staff print it, the governor
decides on paper, staff record the date and contact the requester. (This
matches how the office actually operates today — building a feature
that mirrors the paper process rather than replacing it is deliberate,
not a limitation.)

**Contacting requesters:** email is primary (free). Default: staff send
it manually from the office address using a prefilled link in the staff
view. WhatsApp is secondary: a click-to-chat link with a prefilled
message including the reference number. **No WhatsApp Business API and
no automation** — this was evaluated and declined for cost; see section
2.1. Automated emails only if a free, reliable option fits within its
limits. Propose it and ask first.

## 6. Accessibility (build in from the start)

Target **WCAG 2.1 AA** for visual, auditory, motor and cognitive needs.
Building this in from the start is cheaper than adding it later — don't
treat it as a later pass.

- Semantic HTML, correct heading order, page landmarks, a skip-to-content
  link.
- Everything usable by keyboard alone, with a clearly visible focus
  state.
- Screen-reader support: proper labels on every form field, error
  messages linked to their fields, `lang` set correctly (and updated
  when the language switches).
- Colour contrast of at least 4.5:1, and no information conveyed by
  colour alone.
- Text can be enlarged to 200% without breaking the layout. Offer a
  small text-size and high-contrast toggle.
- Large tap targets, and respect the reduced-motion setting.
- Auditory: no audio-only information. Staff add captions or a transcript
  link for any embedded video.
- Test with keyboard only, a screen reader (NVDA is free on Windows) and
  an automated checker (Lighthouse/axe). Automated tools miss many
  issues, so manual checks are required.

## 7. Security (non-negotiable, think about it in every step)

Assume AI-written code can look good and still be unsafe — this happened
repeatedly while building the earlier version (see the six bugs in
section 2.1). Treat each item below as a requirement and verify it, not
just write it.

- **Database access:** enable Supabase Row Level Security on **every**
  table. Citizens can only insert requests, never read them. Only
  authenticated staff can read and update. **Test this by actually
  trying to read data without logging in** — not by reading the policy
  text and assuming it's correct. After any policy change, also query
  `pg_policies` directly to confirm there's exactly one policy per
  (table, command) pair — see bug 3 in section 2.1 for why this matters.
- **Keys and secrets:** only the public (anon) key may appear in
  front-end code. **Never** expose the service-role key — not in a
  committed file, and not pasted into any chat, ticket, or document.
  Keep secrets in environment files excluded from Git (`.gitignore`),
  and check Git history for leaked keys.
- **Input handling:** validate all input on the server side (not just in
  the browser), enforce length limits, and use the database client's
  safe query methods. No string-built SQL.
- **XSS:** never insert user or staff text into the page as raw HTML.
  News content is plain text or sanitized. Embedded video links are
  restricted to an allowlist of hosts (YouTube/Facebook). (The earlier
  version's escaping approach, confirmed working by testing with a
  literal `<b>test</b>` submission, is a reasonable pattern to reuse.)
- **Uploads:** staff only. Allow images only (check type and size), with
  file-size limits, and strip unsafe filenames.
- **Abuse protection:** add spam protection to the request form (honeypot
  field plus rate limiting, and a free CAPTCHA option if needed).
- **Staff accounts:** strong passwords, only the staff who need access,
  and multi-factor authentication if the platform supports it.
- **HTTPS everywhere.**
- **Privacy:** collect only what is needed, show a short privacy notice
  on the form, never log personal data, and agree a retention period
  with the office for old requests.
- **Dependencies:** keep them minimal, and run the package audit before
  each deploy.
- **Backups:** do not assume they exist. Set up regular exports of the
  requests table and document the restore steps.
- **Security review gates:** before the private test deploy and again
  before any launch, run a dedicated security review of the whole
  codebase against this list and report findings in plain language.
- **Human review:** before public launch, an independent person (a
  developer or the national cybersecurity agency ANTIC, if the office
  can arrange it) should review the site. AI review is not a substitute.

## 8. Design (UI/UX)

The site represents a regional government office. It must look
professional, calm and trustworthy, and work well on small phones.

- Before building any UI, **propose a design direction** (colours,
  typography, layout, tone) and show it to Angel for approval.
- Mobile-first, a small set of reusable components, and consistent
  spacing.
- Fast and light: compressed images, no heavy libraries, no autoplay
  media — real users here are on slow, sometimes expensive connections.
- Accessibility (section 6) is part of the design, not an afterthought.
- Reference points Angel liked for tone, studied for layout patterns
  only (gov.rw's card-based "services" sections; govt.nz's plain,
  content-first, low-imagery restraint) — do not copy either site's
  actual code; describe and rebuild the pattern, not the source.

## 9. Rules for building

- **Plan first, code second.** Each session: propose a short plan, wait
  for approval, then build in small steps.
- **Ask before assuming.** If something is unclear, ask one question at
  a time.
- **No scope additions.** If an idea isn't in this brief, flag it and
  add it to a "later" list. Challenge any idea that adds work. (This
  project has already walked back two mid-build scope expansions once
  each in earlier sessions — an 8-office redesign and a mid-build public
  CMS detour. Both were reasonable ideas individually; both were
  correctly deferred because they weren't needed to solve the core
  problem in section 1. Hold this same line here.)
- **Test every step** and tell Angel exactly how to check it, in a real
  browser — not just "no errors in the syntax check."
- **Commit after every working step and push to GitHub.** Power cuts
  happen.
- **Dev machine is small** (Windows, 4 GB RAM). Avoid heavy tooling and
  many simultaneous processes — see bug 6 in section 2.1 for what
  happens when this is ignored.
- **Handover:** keep `HANDOVER.md` current from day one: every account
  (hosting, database, domain), what it's for, and how to restore the
  site. Accounts should end up owned by the office, not by one person.

## 10. Timeline

- **Start:** Tue 20 Oct 2026. **Target finish:** about 19 Nov 2026.
- **20 to 22 Oct:** audit, plan, site map and design direction approved.
- **23 to 27 Oct:** request flow works end to end (form, database, staff
  view, printable summary), with RLS tested.
- **28 Oct to 3 Nov:** staff login, core pages, bilingual switch, mobile
  layout, accessibility basics, deploy to a private test URL.
- **Checkpoint, Tue 3 Nov:** if the request flow doesn't work by then,
  **cut polish on other pages, not the flow.** Do not extend the
  timeline. (This checkpoint is the single most important discipline in
  this plan — hold it even under pressure to add more scope instead.)
- **4 to 10 Nov:** UI/UX pass, accessibility testing, first security
  review. Remote test with one or two staff. Fill pages with the
  office's content or marked drafts.
- **11 to 14 Nov:** second security review, final fixes, a screen
  recording and screenshots of the working site (fallback for the demo
  in Ebolowa).
- **15 to 19 Nov:** buffer, then travel and present.

## 11. Definition of done

- A citizen can submit a request on a phone and get a reference number.
- A citizen with no email can still have a request registered, by staff,
  on their behalf.
- Staff can log in, see it, update its status and print the summary.
- All six pages exist in French and English. Unverified content is
  clearly marked as draft.
- The security checklist (section 7) has been run and the findings
  fixed or documented.
- Accessibility checks (section 6) done.
- Deployed on a private test URL.
- `HANDOVER.md` is complete.

## 12. Open items (for Angel to confirm with the office)

- Content: history text, official photos, services list, names and
  roles of people in charge.
- **Domain, flagged as important:** a real government site normally sits
  on `.gov.cm`, which is restricted to government and state bodies and
  registered through ANTIC — the inexpensive domain Angel was already
  planning to buy (~7,000 FCFA/year) is almost certainly **not**
  `.gov.cm`, and should not be presented as if it were. A cheap,
  ordinary-looking domain dressed up to resemble an official government
  site is a recognizable phishing pattern, and for a real government
  office specifically, being mistaken for that would be far more
  damaging than the delay of registering properly. Ask Joseph and the
  office how the office should actually be registered; a cheaper domain
  is fine for the **private test URL only**, not for public launch.
- Who in the communications unit will use the news form? What do they
  use today?
- Who owns the hosting and database accounts?
- Retention period for old requests.
- Does the office have rules for publishing an official regional
  website?

## 13. First session (do this, nothing else)

1. Audit the existing code and report what's reusable — read section 2.1
   first, so the audit is checked against what's already confirmed
   working rather than re-discovered from scratch.
2. Propose the architecture and a step-by-step plan for the request
   flow, including how security will be handled.
3. Stop and wait for approval.
