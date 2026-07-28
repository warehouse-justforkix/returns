-- Returns tracker — switch from shared-PIN to email-invite auth.
-- Mirrors the Warehouse Hub model: admins add emails to an invite list; the
-- admin flag always comes from the invite, never the client. Reuses the shared
-- Supabase Auth (auth.users). Idempotent — safe to re-run.

-- ── 1) Profile columns on returns_people ─────────────────────────────────────
alter table returns_people add column if not exists email        text;
alter table returns_people add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
alter table returns_people add column if not exists is_admin     boolean not null default false;
create unique index if not exists returns_people_email_key on returns_people (lower(email)) where email is not null;
create unique index if not exists returns_people_auth_key  on returns_people (auth_user_id)  where auth_user_id is not null;

-- ── 2) Invited emails ────────────────────────────────────────────────────────
create table if not exists returns_invited_emails (
  email      text primary key,          -- stored lowercase
  name       text not null,             -- display name; links to an existing person by name, or creates one
  is_admin   boolean not null default false,
  invited_at timestamptz not null default now()
);

-- ── 3) Helper functions (security definer — avoid RLS recursion) ─────────────
create or replace function public.returns_is_member() returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from returns_people where auth_user_id = auth.uid()) $$;

create or replace function public.returns_is_admin() returns boolean
  language sql stable security definer set search_path = public as
$$ select coalesce((select is_admin from returns_people where auth_user_id = auth.uid()), false) $$;

-- ── 4) Claim/create profile on first login (definer → bypasses RLS to link) ──
create or replace function public.returns_claim_profile()
  returns returns_people language plpgsql security definer set search_path = public as $$
declare
  e   text := lower(auth.email());
  uid uuid := auth.uid();
  inv returns_invited_emails;
  p   returns_people;
  ncolors text[] := array['#4a3aa7','#eb6834','#1baf7a','#eda100','#e34948'];
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- already linked → return now (everyday case; a pure read, no lock, can't hang)
  select * into p from returns_people where auth_user_id = uid;
  if p.id is not null then return p; end if;

  -- otherwise must be invited to link/create
  select * into inv from returns_invited_emails where email = e;
  if inv.email is null then raise exception 'not invited'; end if;

  set local lock_timeout = '4s';   -- fail fast rather than hang if a row is locked

  select * into p from returns_people where lower(email) = e limit 1;        -- link by email…
  if p.id is null then                                                       -- …else claim history by name…
    select * into p from returns_people where name = inv.name and auth_user_id is null limit 1;
  end if;
  if p.id is null then                                                       -- …else create a fresh person
    insert into returns_people (name, email, auth_user_id, is_admin, color)
      values (inv.name, e, uid, inv.is_admin,
              ncolors[1 + (select count(*) from returns_people) % array_length(ncolors,1)])
      returning * into p;
    return p;
  end if;
  update returns_people set auth_user_id = uid, email = e, is_admin = inv.is_admin
    where id = p.id returning * into p;
  return p;
end $$;

-- ── 5) Row-level security: drop anon, add authenticated ──────────────────────
drop policy if exists returns_people_anon_all         on returns_people;
drop policy if exists returns_entries_anon_all         on returns_entries;
drop policy if exists returns_timer_sessions_anon_all  on returns_timer_sessions;
drop policy if exists returns_settings_anon_all         on returns_settings;

-- people: members read all; self or admin edits; admin inserts/deletes
drop policy if exists returns_people_read on returns_people;
create policy returns_people_read on returns_people for select
  to authenticated using (public.returns_is_member());
drop policy if exists returns_people_update on returns_people;
create policy returns_people_update on returns_people for update
  to authenticated using (auth_user_id = auth.uid() or public.returns_is_admin())
  with check (auth_user_id = auth.uid() or public.returns_is_admin());
drop policy if exists returns_people_admin_ins on returns_people;
create policy returns_people_admin_ins on returns_people for insert
  to authenticated with check (public.returns_is_admin());
drop policy if exists returns_people_admin_del on returns_people;
create policy returns_people_admin_del on returns_people for delete
  to authenticated using (public.returns_is_admin());

-- entries: members read all; ADMIN ONLY writes the counts
drop policy if exists returns_entries_read on returns_entries;
create policy returns_entries_read on returns_entries for select
  to authenticated using (public.returns_is_member());
drop policy if exists returns_entries_admin_write on returns_entries;
create policy returns_entries_admin_write on returns_entries for all
  to authenticated using (public.returns_is_admin()) with check (public.returns_is_admin());

-- timer sessions: members read all; each person writes only their OWN (admin any)
drop policy if exists returns_timer_read on returns_timer_sessions;
create policy returns_timer_read on returns_timer_sessions for select
  to authenticated using (public.returns_is_member());
drop policy if exists returns_timer_write on returns_timer_sessions;
create policy returns_timer_write on returns_timer_sessions for all
  to authenticated
  using (public.returns_is_admin() or exists (
    select 1 from returns_people p where p.id = returns_timer_sessions.person_id and p.auth_user_id = auth.uid()))
  with check (public.returns_is_admin() or exists (
    select 1 from returns_people p where p.id = returns_timer_sessions.person_id and p.auth_user_id = auth.uid()));

-- invited emails: admin manages; a signed-in user may read their own row (signup check)
alter table returns_invited_emails enable row level security;
drop policy if exists returns_inv_read on returns_invited_emails;
create policy returns_inv_read on returns_invited_emails for select
  to authenticated using (email = lower(auth.email()) or public.returns_is_admin());
drop policy if exists returns_inv_ins on returns_invited_emails;
create policy returns_inv_ins on returns_invited_emails for insert
  to authenticated with check (public.returns_is_admin());
drop policy if exists returns_inv_upd on returns_invited_emails;
create policy returns_inv_upd on returns_invited_emails for update
  to authenticated using (public.returns_is_admin()) with check (public.returns_is_admin());
drop policy if exists returns_inv_del on returns_invited_emails;
create policy returns_inv_del on returns_invited_emails for delete
  to authenticated using (public.returns_is_admin());

-- settings: admin only (no longer used for the PIN)
drop policy if exists returns_settings_admin on returns_settings;
create policy returns_settings_admin on returns_settings for all
  to authenticated using (public.returns_is_admin()) with check (public.returns_is_admin());

-- ── 6) Grants: revoke anon (login now required), grant authenticated ─────────
revoke all on returns_people, returns_entries, returns_timer_sessions, returns_settings from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on
  returns_people, returns_entries, returns_timer_sessions, returns_settings, returns_invited_emails to authenticated;
grant execute on function public.returns_is_member(), public.returns_is_admin(), public.returns_claim_profile() to authenticated;

-- ── 7) Seed: Karley as permanent admin, linked to her existing history ───────
insert into returns_invited_emails (email, name, is_admin)
  values ('karley@justforkix.com', 'Karley', true)
  on conflict (email) do update set is_admin = true, name = excluded.name;
update returns_people set email = 'karley@justforkix.com' where name = 'Karley' and email is null;

-- retire the old shared PIN
delete from returns_settings where key = 'admin_pin';
