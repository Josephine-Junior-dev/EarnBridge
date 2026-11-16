# EarnBridge
Turn Your Skills Into Income.

EarnBridge is a mobile-first income opportunity and service platform.

## .

## Setup
1. Open the existing Garage Operations Supabase project SQL Editor.
2. Review and run supabase.sql. It creates only eb_-prefixed objects and does not change Garage Operations tables.
3. Enable GitHub Pages for the main branch, root folder.
4. Open the published site and register with email/password.

Never add a service-role/secret key to browser code. Payment webhooks, AI API calls, external data feeds and admin moderation require trusted server-side functions before production use.


## Work Passport setup
1. Open the SQL Editor in the same Supabase project used by Garage Operations.
2. Run `work-passport.sql` once.
3. Refresh EarnBridge and open **Work Passport**.

Work records are self-reported until a genuine customer confirmation flow is implemented. The interface does not claim that an evidence URL or provider submission verifies a job. Customer verification, secure evidence uploads, payment escrow and production subscriptions still require trusted server-side workflows before commercial launch.


## Commercial order workflow (new)
1. In the existing Garage Operations Supabase project, run `commerce-core.sql` once in SQL Editor.
2. Refresh the EarnBridge site after GitHub Pages finishes deploying.
3. Publish a service from **My services** using a second test account.
4. Sign in as a different account, open **Browse services**, and request that service.
5. Sign back in as the provider and open **Orders & delivery** to accept, start and submit delivery.
6. Sign in as the customer to confirm completion or raise a dispute. Either participant can leave one review after completion.

### Important production limitations
- This workflow creates real database orders, enforces participant-specific status transitions, locks the agreed order terms, and records an order event history.
- It does **not** collect or hold money. Do not describe it as escrow or payment protection. M-Pesa/card collection, provider payouts, verified payment webhooks, milestone escrow, dispute operations and admin tooling are separate production work.
- Test with two different accounts. A single account cannot act as both customer and provider on one order.
- Do not run the original `supabase.sql` again if the EarnBridge schema already exists; use the dedicated `commerce-core.sql` migration for this workflow.


## SaaS workspace modules
The current workspace includes:
- Business centre for owner-managed business profiles.
- Reports with real order/earnings totals, pipeline summaries and CSV export.
- Free, Professional and Business plan pages with upgrade requests.
- A restricted administration workspace for opportunity moderation, user/business counts, safety reports and plan-request review.
- Marketplace provider profiles are loaded separately from services because the database uses auth-user references rather than a direct profile foreign key.

### Required database setup
Run these scripts in the SQL Editor of the existing Garage Operations Supabase project, in this order, if they have not already been run:
1. `supabase.sql`
2. `commerce-core.sql`
3. `work-passport.sql`
4. `saas-core.sql`

Do not re-run the base schema on a live database without reviewing its policies first. The migrations are intended to create or extend only EarnBridge's `eb_` objects.

### Granting platform administration
Admin rights are not self-service. After the account has registered, an existing project owner must run a statement like this in Supabase SQL Editor, replacing the email with the exact admin account email:

```sql
insert into public.eb_admins(user_id, role)
select id, 'admin' from auth.users where lower(email)=lower('YOUR-ADMIN-EMAIL')
on conflict (user_id) do update set role='admin';
```

Do not expose admin privileges through browser-side code.

### Payment and subscription status
The plan page currently records upgrade requests only. It does not charge a card or initiate an M-Pesa STK push, and an approved request is not an active paid subscription. Live collection, payment verification, subscription activation, receipts and refunds require a trusted server-side payment integration and verified provider callbacks. Never write payment success from the browser.

### Deployment and testing
GitHub Pages serves the frontend after the repository commits finish deploying. Test with at least two separate user accounts:
- Account A publishes a service.
- Account B requests the service and sees it under Orders.
- Account A accepts, starts and submits delivery.
- Account B confirms completion or raises a dispute.
- Both accounts check their own reports and records.


## Verified Job Proof and customer confirmation (new)

This module adds private work evidence and customer-email confirmation to Work Passport.

### Database migration

After the existing EarnBridge migrations have been applied, run `verified-job-proof.sql` in the SQL Editor of the same Garage Operations Supabase project. It:
- Removes direct worker privileges to set a work record to `verified`.
- Allows workers to create and edit only self-reported work details.
- Stores verification requests and immutable customer-response events.
- Creates a private `eb-work-evidence` Storage bucket with owner-folder policies.
- Adds a single-use, seven-day customer confirmation RPC.

Do not skip this migration. The older `work-passport.sql` by itself does not enforce customer confirmation.

### Deploy the confirmation email function

The repository includes `supabase/functions/send-job-confirmation/index.ts`. Deploy it as the Supabase Edge Function named `send-job-confirmation` with JWT verification enabled.

Configure these Edge Function secrets:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-side secret only; never put this in config.js or browser code)
- `RESEND_API_KEY`
- `EARNBRIDGE_SITE_URL` (the deployed EarnBridge GitHub Pages base URL, without a trailing slash)
- `EMAIL_FROM` (a verified sender address in Resend)

The function checks the signed-in worker owns the record, creates a random one-time confirmation token on the server, and emails the customer a link to `confirm.html`. The raw token is never returned to the worker's browser. The customer can confirm or reject without creating an EarnBridge account.

### Important trust boundary

The public Work Passport at `passport.html?id=<profile-id>` displays only public profile fields, listed skills and customer-confirmed work. It deliberately excludes customer names/emails, job amounts and private evidence paths. The signed-in owner can copy the public link or display a QR code from Work Passport.\n\nThe new badge means the confirmation link was used by someone with access to the customer email inbox. It does not independently establish the customer's legal identity, the quality of the work, payment, or professional licensing. Collusion and false customer email addresses remain possible and need additional anti-fraud controls before any guarantee is marketed.

### Test the complete flow

1. Apply `verified-job-proof.sql`.
2. Deploy the Edge Function and configure the six secrets above.
3. Sign in to EarnBridge and open **Work Passport**.
4. Add a test work record using an email inbox you control separately from the worker account.
5. Attach a small JPG/PNG/PDF evidence file and save.
6. Choose **Email customer to confirm**.
7. Open the email in the separate customer inbox and confirm or reject.
8. Return to Work Passport and check the status and verification history.

If email delivery is not configured, the request button will return a clear setup error. Do not manually mark records as verified.

## Commercial readiness notes

The existing workspace already contains the marketplace, opportunities, service catalogue, customer leads/enquiries, order workflow, businesses, reports, earnings ledger and plan-request pages. Those are functional foundations, not proof that every SaaS capability is production-complete.

Live M-Pesa/card collection, escrow, milestone fund release, automatic subscription billing, refunds, automated matching and formal identity checks are not enabled by this commit. Upgrade requests do not collect money or activate paid access.
## Career selector and skills directory

The profile now includes a selectable career / professional role. The My Skills section includes a starter directory grouped into Automotive & Transport, Construction & Trades, Home & Facility Services, Technology & Digital, Business & Administration, Beauty / Health / Wellness, Food & Hospitality, Creative & Media, Education & Professional, and Retail & Agriculture. Users can search their own skills, choose a suggested skill, or type a custom skill.

Run the updated `verified-job-proof.sql` migration in the existing Supabase project to add `eb_profiles.career` and `eb_skills.category`, and update the public Work Passport response. Existing skill records are preserved and receive the category `Other` by default. The directory is a suggestion catalogue; it does not automatically claim that a user possesses any listed skill. Users must add their own skills and select their actual experience level.
