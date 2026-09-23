# Setting up accounts: Supabase, Google, and Apple

The prototype signs people in three ways: **Google**, **Apple**, and an **email link** (no password). All three run through Supabase Auth.

Secrets (the Google client secret and the Apple private key) only ever go into the Supabase dashboard. Never put them in this repo or in the app. The app only needs the project URL and the anon (publishable) key, which are safe to ship because every table is protected by row-level security.

The redirect address the app listens on is **`understudy://auth-callback`**.

---

## 1 · Supabase project (about 10 minutes)

1. Create a project: <https://supabase.com/dashboard/new>. Pick a region close to your users (for Peru, `sa-east-1` São Paulo or `us-east-1`).
2. **Create the tables.** Open the SQL editor, paste all of `supabase/migrations/0001_accounts_and_skills.sql` and run it, then do the same with `0002_receipt_details.sql`.
3. **Let the app open sign-in links.** Go to Authentication → URL Configuration → Redirect URLs, and add `understudy://auth-callback`.
4. **Turn on email links.** Go to Authentication → Sign In / Providers → Email, and make sure it's enabled. The default Supabase mail server only sends a few emails an hour. That's fine for testing, but add your own SMTP before inviting testers.
5. **Connect the app.** Go to Project Settings → API Keys and copy the **Project URL** and the **anon / publishable key** into `app/config.local.json`:
   ```json
   { "supabaseURL": "https://abcd1234.supabase.co", "supabaseAnonKey": "sb_publishable_…" }
   ```
   Git ignores this file. Then rebuild with `app/scripts/bundle.sh`.

At this point email-link sign-in works.

## 2 · Google sign-in (about 15 minutes)

1. Open Google Cloud and create a project, for example "Understudy": <https://console.cloud.google.com/projectcreate>
2. **Set up the consent screen.** Go to the Google Auth Platform: <https://console.cloud.google.com/auth/overview>. Choose **External**, and leave it in **Testing**. Add yourself (and any testers, up to 100) as test users. Sign-in only needs the basic scopes: `openid`, `email`, and `profile`.
3. **Create the OAuth client.** Go to Clients → Create client → **Web application**, and add this under Authorized redirect URIs:
   `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`
   (It's the Supabase callback, not the `understudy://` address. Supabase hands the result to the app.)
4. **Add it to Supabase.** In Supabase, go to Authentication → Sign In / Providers → Google, turn it on, and paste the **Client ID** and **Client secret**.

The Google Sheets permission is a separate, later step. Sign-in only asks for name and email.

## 3 · Apple sign-in (about 20 minutes, needs a paid Apple account)

Sign in with Apple requires the **Apple Developer Program** ($99 a year): <https://developer.apple.com/programs/enroll/>. You need the same membership later anyway, to sign and notarize the public download.

1. **Create an App ID.** Go to Identifiers: <https://developer.apple.com/account/resources/identifiers/list>. Create an App ID (for example `app.understudy`) with **Sign in with Apple** enabled.
2. **Create a Services ID.** Create one (for example `app.understudy.signin`), enable Sign in with Apple, and configure it:
   - Domain: `YOUR_PROJECT_REF.supabase.co`
   - Return URL: `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`
3. **Create a key.** Go to Keys: <https://developer.apple.com/account/resources/authkeys/list>. Create a key with Sign in with Apple, then download the `.p8` file. Note the **Key ID** and your **Team ID**.
4. **Add it to Supabase.** In Supabase, go to Authentication → Sign In / Providers → Apple and turn it on. Enter the Services ID as the client ID, then generate the client secret from the `.p8` key, Key ID, and Team ID (Supabase's Apple provider guide links to a generator).
   **The generated secret expires within 6 months.** Set a reminder to regenerate it, or Apple sign-in will stop working.

Keep the `.p8` file out of this repo. `.gitignore` blocks `*.p8` as a safety net, but the right place for it is a password manager.

---

## Checking it works

1. Build and open the app:
   - `app/scripts/bundle.sh`
   - `open app/build/Understudy.app`
2. In the main window, open **Account** in the sidebar. Without a config file, it says sign-in isn't set up and the app stays in Sample mode.
3. Try each method. After signing in, the Account page shows your email and "Free plan · 0 of 5 skills used", and Skills shows the sample skill.
4. In Supabase, go to Table Editor → `skills`. You should see one row with your user ID and `is_sample = true`. That confirms row-level security and the sign-up trigger are working.

## What isn't set up yet

- **Google Sheets access:** read-only for rehearsal. This comes with the Sheets connector build.
- **The server-side AI proxy:** a Supabase Edge Function that holds the Anthropic API key. This comes with the first run.
- **Billing and plan changes.**
