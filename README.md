# Salesman Tracker

BNE field-sales platform for Android, iOS, web, and an administrator dashboard.
It records attendance, manages customers and orders, verifies field visits with
customer OTP + GPS, captures visit reports, and provides management reporting.

## Current product surfaces

- Flutter sales app: Android, iOS, and web from one codebase.
- Admin dashboard: responsive static web application.
- Supabase: PostgreSQL, Auth, Storage, Row Level Security, and Edge Functions.
- MSG91: WhatsApp OTP with SMS fallback.
- GitHub Actions: analyzes and builds the app, publishes the Android APK, and
  deploys the web app + admin dashboard to GitHub Pages.

Production links:

- Sales web app: <https://manubne.github.io/salesman-tracker/>
- Admin dashboard: <https://manubne.github.io/salesman-tracker/admin.html>
- Android APK: <https://github.com/manubne/salesman-tracker/releases/tag/latest>

## Repository layout

```text
app/                    Flutter source
admin/index.html        Admin dashboard source
supabase/migrations/    Reproducible database schema and security policies
supabase/functions/     OTP and messaging Edge Functions
.github/workflows/      Build and deployment automation
docs/                   Audit and development notes
```

The Flutter source is committed normally. Do not reintroduce base64 ZIP files;
they made code review and reliable deployments unnecessarily difficult.

## Supabase deployment

For the existing production project, mark the two manually applied baseline
migrations as applied, then push the stabilization migration:

```bash
supabase login
supabase link --project-ref hyrqqjeplichtfpcfxnb
supabase migration repair --status applied 202607050001 202607050002
supabase db push
```

Deploy all Edge Functions:

```bash
supabase functions deploy request-visit-otp
supabase functions deploy verify-visit-otp
supabase functions deploy verify-customer-mobile
supabase functions deploy send-sms --no-verify-jwt
```

Required secrets:

```bash
supabase secrets set MSG91_AUTHKEY=...
supabase secrets set MSG91_WA_NUMBER=91XXXXXXXXXX
supabase secrets set MSG91_WA_TEMPLATE=visit_otp
supabase secrets set MSG91_SMS_TEMPLATE_ID=...
supabase secrets set SEND_SMS_HOOK_SECRET=...
```

`SEND_SMS_HOOK_SECRET` is mandatory. The login messaging function now fails
closed if the Supabase Auth Hook signature cannot be verified.

In Supabase Auth, configure the Send SMS hook to call `send-sms`. Phone sign-in
from the app uses `shouldCreateUser: false`, so unknown numbers cannot create
their own company account.

## User provisioning

1. Create the user in Supabase Authentication.
2. The database trigger creates an inactive profile.
3. Set the user's name, role, territory, and `active = true` in `public.users`.
4. Only `admin` gets company-wide dashboard access. `sales` and `manager`
   remain limited to their own records until team-scoped manager access is built.

For an email administrator, create and confirm the Auth user, then run:

```sql
update public.users u
set name = 'Manu', role = 'admin', active = true
from auth.users a
where a.id = u.id and a.email = 'YOUR_ADMIN_EMAIL';
```

## Local Flutter setup

The generated platform folders are intentionally excluded from Git. Create
them on a development machine with Flutter installed:

```bash
cd app
flutter create --platforms=android,ios,web .
flutter pub get
flutter analyze
flutter run
```

The production Supabase URL and publishable key are safe client configuration
and are the defaults. A staging project can be selected without editing source:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

CI adds the required Android and iOS location/camera permission descriptions.
For local mobile builds, add the same permissions shown in the workflow.

## Production scheduling

Schedule this query hourly with Supabase Cron so overdue planned visits become
missed automatically:

```sql
select public.mark_missed_visits();
```

## Next product phases

The immediate foundation and security gaps are addressed in the stabilization
migration. The remaining major product work is:

1. Admin user management and team assignment.
2. Manager dashboard restricted to assigned team members.
3. Device binding and device reset controls.
4. Photo watermarking with server time and coordinates.
5. Offline cache/outbox and delayed synchronization.
6. Notifications, scheduled follow-ups, and quote workflow.
7. Automated tests, pilot telemetry, and App Store/TestFlight delivery.

See `docs/PROJECT_AUDIT_2026-07-18.md` for the detailed baseline.
