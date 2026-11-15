# EarnBridge
Turn Your Skills Into Income.

EarnBridge is a mobile-first income opportunity and service platform.

## Supabase
This app reuses the existing Garage Operations Pro Supabase project and its browser publishable key, centralized in config.js. All EarnBridge records use eb_-prefixed tables and their own RLS policies. This is logical separation inside a shared database, not physical database isolation.

## Setup
1. Open the existing Garage Operations Supabase project SQL Editor.
2. Review and run supabase.sql. It creates only eb_-prefixed objects and does not change Garage Operations tables.
3. Enable GitHub Pages for the main branch, root folder.
4. Open the published site and register with email/password.

Never add a service-role/secret key to browser code. Payment webhooks, AI API calls, external data feeds and admin moderation require trusted server-side functions before production use.
