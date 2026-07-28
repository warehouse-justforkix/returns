-- Fix Returns login: clear the stuck profile-claim jam, pre-link Karley as admin
-- (so her sign-in is a pure read — nothing to lock), and make the claim function
-- SELECT-first + lock-safe so it can never hang again. Idempotent.

-- 1) Kill any stuck/blocked claim transactions holding a row lock
select pg_terminate_backend(pid)
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
  and (query ilike '%returns_claim_profile%' or query ilike '%returns_people%')
  and state <> 'idle'
  and now() - query_start > interval '3 seconds';

-- 2) Make sure Karley is invited as admin, and pre-link her to her history +
--    her existing auth account → her login returns instantly with no write.
insert into returns_invited_emails (email, name, is_admin)
  values ('karley@justforkix.com', 'Karley', true)
  on conflict (email) do update set is_admin = true, name = 'Karley';

update returns_people p
   set auth_user_id = u.id, email = 'karley@justforkix.com', is_admin = true
  from auth.users u
 where u.email = 'karley@justforkix.com' and p.name = 'Karley';

-- 3) Robust claim: return immediately if already linked (pure read, no lock),
--    only write on the first link/create, and fail fast instead of hanging.
create or replace function public.returns_claim_profile()
  returns returns_people language plpgsql security definer set search_path = public as $$
declare
  e text := lower(auth.email());
  uid uuid := auth.uid();
  inv returns_invited_emails;
  p   returns_people;
  ncolors text[] := array['#4a3aa7','#eb6834','#1baf7a','#eda100','#e34948'];
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- already linked → return now (the everyday case; no write, no lock)
  select * into p from returns_people where auth_user_id = uid;
  if p.id is not null then return p; end if;

  -- otherwise must be invited to link/create
  select * into inv from returns_invited_emails where email = e;
  if inv.email is null then raise exception 'not invited'; end if;

  set local lock_timeout = '4s';   -- fail fast rather than hang if a row is locked

  select * into p from returns_people where lower(email) = e limit 1;        -- link by email…
  if p.id is null then
    select * into p from returns_people where name = inv.name and auth_user_id is null limit 1;  -- …or claim history by name
  end if;
  if p.id is null then                                                       -- …or create fresh
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
