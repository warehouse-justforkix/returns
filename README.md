# Returns & Refunds Tracker

Internal productivity tracker for the JFK returns/refunds team (Karley + Riley).
Logs daily refund counts per person, times processing with a start/stop timer, and
charts speed against a goal.

## What it does

- **Timer** — each person picks their name and hits Start/Stop. Elapsed time banks
  into that day's **Hours Spent** (multiple sessions/day accumulate).
- **Daily counts** — Amazon · Shopify · Program · AT Errors. **Daily Total =**
  the sum of all four (AT Errors *is* part of the count). **Avg/Hour = Total ÷ Hours.**
- **Admin (Karley)** enters the counts for either person, any date, behind a shared
  PIN lock. Staff run their own timer and view everyone's stats — but can't edit counts.
- **Charts** — daily total over time (both people), speed (avg/hr) vs. a goal line,
  and channel mix. Stat tiles show each person's rolling speed, best day, and goal
  progress. Everything filters by 30d / 90d / all-time and by person or Team.

## Stack

Static site (no build): `index.html` + `style.css` + `app.js`, talking straight to
Supabase via `@supabase/supabase-js` (ESM). Charts via Chart.js (ESM). Reuses the
shared JFK Supabase project (`iptnlqfitvmoiofzrmvx`) with `returns_`-prefixed tables,
so it's independent of the Warehouse Hub.

- `config.js` — Supabase URL + anon key
- `db/setup.sql` — schema, generated `daily_total`, triggers, RLS
- `db/seed.sql` — historical data (106 entries, 11/2025–7/2026), idempotent
- `db/install.sql` — setup + seed bundled, for a one-shot paste into the SQL editor

## First-time setup

Run `db/install.sql` once in the Supabase SQL editor (or let Claude apply it via the
connector). Then open the site. The first person to unlock **Admin** sets the shared PIN.

> Security note: the app uses the public anon key with permissive RLS on the
> `returns_*` tables — fine for an internal tool, but anyone with the URL + PIN can
> edit. The PIN is a soft gate, not real auth. Ask to add Supabase Auth if needed.

## Local preview

```sh
python3 -m http.server 8777   # then open http://localhost:8777
```

## Deploy

Static — host anywhere (GitHub Pages like the Warehouse Hub, Vercel, etc.).
