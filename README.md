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
