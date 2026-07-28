# Returns & Refunds Tracker

Internal productivity tracker for the JFK returns/refunds team (Karley + Riley).
Logs daily refund counts per person, times processing with a start/stop timer, and
charts speed against a goal.

## What it does

- **Timer** — each person picks their name and hits Start/Stop. Elapsed time banks
  into that day's **Hours Spent** (multiple sessions/day accumulate).
- **Daily counts** — Amazon · Shopify · Program · AT Errors. **Daily Total =**
  the sum of all four (AT Errors *is* part of the count). **Avg/Hour = Total ÷ Hours.**
- **Accounts by invite** — Karley (admin) adds an email in the Invites panel; that
  person signs up with the invited email and is linked to their profile automatically
  (the admin flag comes from the invite, never the client). Un-invited emails can make
  an auth account but get no access.
- **Admin (Karley)** enters the counts for either person, any date. Staff sign in, run
  their own timer, and view everyone's stats — but can't edit counts (enforced by RLS).
- **Charts** — daily total over time (both people), speed (avg/hr) vs. a goal line,
  and channel mix. Stat tiles show each person's rolling speed, best day, and goal
  progress. Everything filters by 30d / 90d / all-time and by person or Team.

## Stack

Static site (no build): `index.html` + `style.css` + `app.js`, talking straight to
Supabase via `@supabase/supabase-js` (ESM). Charts via Chart.js (ESM). Reuses the
shared JFK Supabase project (`iptnlqfitvmoiofzrmvx`) with `returns_`-prefixed tables,
so it's independent of the Warehouse Hub.

Auth is Supabase Auth (email + password; "Confirm email" is off for frictionless
signup). Authorization is enforced by row-level security: reads require a linked
profile; **only an admin can write the count columns**; each person writes only their
own timer sessions. Hours are *derived* — an entry's stored `hours_spent` (historical /
manual base) plus the duration of that day's completed timer sessions.

- `config.js` — Supabase URL + anon key
- `db/setup.sql` — base schema, generated `daily_total`, triggers
- `db/seed.sql` — historical data (106 entries, 11/2025–7/2026), idempotent
- `db/install.sql` — setup + seed bundled, one-shot paste for a fresh project
- `db/auth.sql` — email-invite auth: `returns_invited_emails`, profile columns on
  `returns_people`, the `returns_claim_profile()` RPC, RLS, and Karley seeded as admin

## First-time setup

On a fresh project run `db/install.sql` then `db/auth.sql` in the Supabase SQL editor.
Karley (`karley@justforkix.com`) is seeded as admin — she signs up once with that email,
then invites everyone else from the **Invites** panel.

> Security note: real logins now gate all data (the anon key alone can read/write
> nothing). To link a returning person to their existing history, invite them with the
> **same display name** as their historical rows (e.g. "Riley").

## Local preview

```sh
python3 -m http.server 8777   # then open http://localhost:8777
```

## Deploy

Static — host anywhere (GitHub Pages like the Warehouse Hub, Vercel, etc.).
