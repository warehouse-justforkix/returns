-- Returns / Refunds tracker — schema
-- Runs on the shared JFK Supabase project (iptnlqfitvmoiofzrmvx), namespaced with
-- a `returns_` prefix so it stays independent of the Warehouse Hub tables.
-- Idempotent: safe to run more than once.

-- ── People (profiles) ────────────────────────────────────────────────────────
create table if not exists returns_people (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  color      text,                       -- hex used for this person's series in charts
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- ── Daily entries — one row per person per day ───────────────────────────────
create table if not exists returns_entries (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references returns_people(id) on delete cascade,
  entry_date  date not null,
  amazon      integer not null default 0,
  shopify     integer not null default 0,
  program     integer not null default 0,
  at_errors   integer not null default 0,
  hours_spent numeric(6,2) not null default 0,
  note        text,
  -- Daily Total = Amazon + Shopify + Program + AT Errors (AT is part of the count)
  daily_total integer generated always as (amazon + shopify + program + at_errors) stored,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (person_id, entry_date)
);
create index if not exists returns_entries_date_idx on returns_entries (entry_date);

-- keep updated_at fresh
create or replace function returns_touch_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;
drop trigger if exists returns_entries_touch on returns_entries;
create trigger returns_entries_touch before update on returns_entries
  for each row execute function returns_touch_updated_at();

-- ── Timer sessions — start/stop stamps that roll up into hours_spent ─────────
create table if not exists returns_timer_sessions (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null references returns_people(id) on delete cascade,
  entry_date date not null,
  started_at timestamptz not null default now(),
  ended_at   timestamptz,                 -- null = still running
  created_at timestamptz not null default now()
);
create index if not exists returns_timer_person_idx on returns_timer_sessions (person_id, entry_date);

-- ── Settings (shared key/value — e.g. the admin PIN) ─────────────────────────
create table if not exists returns_settings (
  key   text primary key,
  value text
);

-- ── Row-level security ───────────────────────────────────────────────────────
-- This is a low-stakes internal productivity tracker used with the shared anon
-- key (no per-person login). Anon may read/write ONLY these three tables; RLS on
-- every other table in the project is untouched. Tighten later if wanted.
alter table returns_people          enable row level security;
alter table returns_entries         enable row level security;
alter table returns_timer_sessions  enable row level security;
alter table returns_settings        enable row level security;

do $$
declare t text;
begin
  foreach t in array array['returns_people','returns_entries','returns_timer_sessions','returns_settings'] loop
    execute format('drop policy if exists %I_anon_all on %I', t, t);
    execute format(
      'create policy %I_anon_all on %I for all to anon using (true) with check (true)',
      t, t);
  end loop;
end $$;

-- Table-level grants for the anon role. RLS policies above gate which ROWS are
-- visible; these grants give the role table access in the first place. Raw
-- CREATE TABLE in the SQL editor does not grant these automatically.
grant usage on schema public to anon;
grant select, insert, update, delete on
  returns_people, returns_entries, returns_timer_sessions, returns_settings to anon;
