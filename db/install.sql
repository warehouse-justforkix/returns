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

-- ═══════════════ SEED DATA ═══════════════
-- Seed data for returns tracker (generated from historical sheet, 106 entries)
-- Idempotent: safe to re-run. People upserted by name; entries upserted by (person, date).

insert into returns_people (name, color) values
  ('Karley', '#2a78d6'),
  ('Riley',  '#008300')
on conflict (name) do nothing;

insert into returns_entries (person_id, entry_date, amazon, shopify, program, at_errors, hours_spent, note) values
  ((select id from returns_people where name = 'Karley'), '2025-11-26', 178, 0, 0, 0, 5, null),
  ((select id from returns_people where name = 'Riley'), '2025-11-26', 0, 108, 0, 0, 5, null),
  ((select id from returns_people where name = 'Karley'), '2025-11-28', 140, 0, 68, 19, 6, null),
  ((select id from returns_people where name = 'Riley'), '2025-11-28', 0, 59, 45, 75, 6.5, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-08', 73, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-09', 111, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-10', 0, 40, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-15', 32, 0, 0, 0, 1, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-15', 0, 20, 0, 0, 1, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-16', 0, 0, 107, 65, 0, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-16', 0, 7, 54, 36, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-17', 6, 0, 53, 43, 0, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-17', 0, 9, 37, 33, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-18', 0, 0, 6, 5, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-19', 19, 0, 28, 21, 0, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-19', 3, 0, 11, 3, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-22', 0, 0, 29, 15, 0.67, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-22', 0, 0, 34, 22, 1.63, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-26', 21, 0, 53, 32, 0, null),
  ((select id from returns_people where name = 'Karley'), '2025-12-29', 50, 6, 0, 0, 0.72, null),
  ((select id from returns_people where name = 'Riley'), '2025-12-29', 0, 24, 0, 0, 1, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-02', 9, 1, 8, 3, 0.67, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-08', 0, 34, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-09', 113, 0, 0, 0, 3, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-09', 50, 25, 17, 15, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-13', 0, 0, 65, 29, 0, 'Covers 1/13-1/15'),
  ((select id from returns_people where name = 'Riley'), '2026-01-16', 56, 15, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-19', 0, 0, 85, 31, 0, 'Covers 1/19, 1/22, 1/23'),
  ((select id from returns_people where name = 'Karley'), '2026-01-22', 51, 0, 45, 31, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-23', 24, 1, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-23', 3, 48, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-26', 0, 0, 10, 7, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-26', 0, 0, 3, 15, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-27', 32, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-27', 3, 0, 8, 13, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-28', 42, 4, 10, 8, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-28', 0, 21, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-29', 10, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-29', 0, 7, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-01-30', 5, 2, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-01-30', 0, 0, 16, 11, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-03', 9, 8, 17, 14, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-04', 28, 18, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-05', 53, 4, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-02-09', 0, 0, 58, 38, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-09', 20, 12, 1, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-02-10', 16, 5, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-12', 31, 18, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-13', 38, 16, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-16', 0, 0, 56, 24, 0, 'Covers 2/16-2/17'),
  ((select id from returns_people where name = 'Karley'), '2026-02-17', 0, 0, 13, 8, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-02-18', 3, 0, 5, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-18', 63, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-19', 1, 33, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-20', 19, 19, 5, 4, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-23', 12, 7, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-02-27', 39, 29, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-03-02', 0, 0, 50, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-09', 0, 50, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-10', 26, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-11', 38, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-12', 14, 18, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-13', 42, 9, 18, 8, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-16', 0, 0, 28, 12, 0, 'Covers 3/16, 3/17, 3/18'),
  ((select id from returns_people where name = 'Karley'), '2026-03-18', 18, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-19', 0, 0, 38, 18, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-03-20', 62, 2, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-20', 0, 43, 7, 2, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-03-23', 17, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-27', 49, 40, 4, 2, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-03-31', 28, 13, 9, 5, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-04-01', 33, 3, 3, 1, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-04-06', 35, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-04-07', 0, 22, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-04-17', 76, 22, 3, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-04-24', 27, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-04-28', 53, 8, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-04-29', 0, 5, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-04-29', 0, 35, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-04-30', 37, 1, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-01', 8, 9, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-06', 35, 3, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-07', 27, 17, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-05-08', 6, 3, 9, 2, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-15', 55, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-18', 0, 22, 18, 2, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-21', 8, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-05-21', 50, 44, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-05-22', 0, 0, 21, 9, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-05-28', 33, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-05-28', 0, 13, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-06-01', 18, 0, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-06-02', 13, 9, 6, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-02', 0, 6, 0, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-06-04', 9, 2, 1, 3, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-04', 4, 4, 0, 2, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-08', 17, 9, 7, 2, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-09', 11, 4, 1, 0, 0, null),
  ((select id from returns_people where name = 'Karley'), '2026-06-11', 14, 9, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-16', 19, 2, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-19', 13, 14, 14, 12, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-06-22', 27, 18, 0, 0, 0, 'Covers 6/22,6/23'),
  ((select id from returns_people where name = 'Riley'), '2026-06-25', 15, 3, 0, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-07-02', 22, 6, 2, 2, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-07-09', 32, 7, 1, 0, 0, null),
  ((select id from returns_people where name = 'Riley'), '2026-07-16', 11, 0, 1, 0, 0, null)
on conflict (person_id, entry_date) do update set
  amazon = excluded.amazon, shopify = excluded.shopify, program = excluded.program,
  at_errors = excluded.at_errors, hours_spent = excluded.hours_spent, note = excluded.note;
