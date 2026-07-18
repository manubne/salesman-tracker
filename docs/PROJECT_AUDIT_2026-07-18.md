# Project audit — 18 July 2026

## Executive result

The project is beyond prototype stage: the Android/web build pipeline succeeds,
an APK and GitHub Pages deployment exist, Supabase is live, and the core screens
for customers, visits, attendance, orders, and reporting are implemented.

It was not yet safe to extend as-is. The repository stored the real Flutter app
inside a base64 ZIP, omitted the live Orders database schema, and contained
authorization and visit-integrity gaps. This stabilization branch converts the
repository into normal source code and adds a reproducible database migration.

## Verified as implemented

| Area | Status | Notes |
|---|---|---|
| Mobile/web sales app | Implemented | Flutter UI for login, customers, visits, attendance, reports, orders, and profile. |
| Admin dashboard | Implemented | Overview, visits, map, customers, orders, requirements, attendance, team, CSV export. |
| Android build | Working | GitHub Actions run 36 succeeded; release APK exists. |
| Web/admin hosting | Working | Both surfaces are deployed on GitHub Pages. |
| Supabase core tables | Live | Users, customers, visits, OTPs, requirements, photos, attendance, audit. |
| Orders tables | Live but previously undocumented | `order_categories`, `orders`, and `order_files` respond in production but were absent from source schema. |
| Visit OTP functions | Implemented | WhatsApp-first, SMS fallback, hash storage, expiry, attempts, resend limit. |
| GPS verification | Implemented | Accuracy, mock-location, distance, and anomaly flags are captured. |

## Critical findings corrected

1. **The core verification trigger could discard server verification data.**
   A service-role request bypasses RLS but not PostgreSQL triggers. The old
   trigger could preserve the old empty GPS/verification fields while changing
   only the status. The replacement explicitly trusts server/service calls and
   prevents a sales user from moving a planned visit directly to verified.

2. **Unknown phone numbers could self-register.**
   OTP login used the default create-user behavior. The app and admin login now
   use `shouldCreateUser: false`; newly provisioned profiles default inactive.

3. **Deactivated users retained access to their own business data.**
   RLS checked record ownership but not user activation. Canonical policies now
   require both ownership and an active account.

4. **Manager meant full admin in the database.**
   The old helper treated `manager` as company-wide admin. Until team mapping is
   implemented, only the `admin` role has global access.

5. **Email admin provisioning was not repeatable.**
   The user trigger inserted an empty mobile into a unique, non-null column.
   Multiple email users therefore conflicted. Mobile is now nullable and empty
   values are normalized to null.

6. **Customer mobile verification existed only in the backend.**
   No screen called it. Customer creation now immediately requests and verifies
   the OTP, unverified customers can be retried from the customer list, and only
   verified customers can be used for planned visits.

7. **Attendance trusted the employee device clock.**
   Attendance now goes through a PostgreSQL RPC that records server time and
   saves GPS accuracy/mock-location signals.

8. **Storage security was documented as comments, not deployable SQL.**
   Private buckets and owner/admin upload/read policies are now in migration.

9. **OTP generation and messaging-hook safety needed hardening.**
   OTPs now use cryptographic randomness, function inputs are validated, active
   accounts are enforced, customer resend abuse is limited, and the Auth hook
   rejects unsigned requests.

10. **The repository was not maintainable.**
    Multiple encoded/partial app copies could silently diverge. The canonical
    Flutter, Supabase, and admin sources are now directly versioned.

## Important work still pending

| Priority | Work | Reason |
|---|---|---|
| P0 | Apply the stabilization migration and redeploy functions | Code changes depend on the new RLS/RPC definitions. |
| P0 | Run the GitHub build after merge and complete a real-device smoke test | Local Flutter SDK is not present in the audit environment. |
| P1 | Admin user creation/deactivation UI | Current provisioning still requires Supabase administration. |
| P1 | Device binding | Field credential sharing remains possible. |
| P1 | Photo watermarking | Camera-only capture is present, but timestamp/coordinate watermark is not. |
| P1 | Manager/team model | Manager role is safe but not yet useful across a team. |
| P2 | Offline mode | Customer/visit cache and retry outbox are not implemented. |
| P2 | Quote and follow-up notifications | Orders can reach “Need quote,” but alerting and quote assignment are incomplete. |
| P2 | Automated test suite | CI now analyzes source, but unit/widget/integration coverage must be added. |
| P2 | iOS distribution | Source is cross-platform; signing, TestFlight, and App Store setup remain. |

## Recommended next build sequence

1. Deploy this stabilization safely and pilot with two internal users.
2. Build admin user management + team assignment.
3. Enforce device binding and add administrator reset.
4. Add watermarked photos and visit exception review.
5. Add notifications/quote ownership and weekly management reports.
6. Build offline sync, then expand the pilot before full rollout.
