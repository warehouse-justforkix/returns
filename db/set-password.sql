-- Set a known password for Karley directly (bypasses the broken reset email).
-- Works for BOTH the Returns app and the Warehouse Hub — it's one shared account.
-- After running, sign in with:  karley@justforkix.com  /  JustforKix2026
create extension if not exists pgcrypto with schema extensions;

update auth.users
   set encrypted_password  = extensions.crypt('JustforKix2026', extensions.gen_salt('bf')),
       email_confirmed_at  = coalesce(email_confirmed_at, now()),
       recovery_token      = '',
       recovery_sent_at    = null,
       updated_at          = now()
 where email = 'karley@justforkix.com';
