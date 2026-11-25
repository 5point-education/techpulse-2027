# TECHPULSE 2027 Registration Portal

A responsive visitor, participant and event-operations portal for TECHPULSE 2027. The implementation follows the supplied UI/UX proposal: cyan visitor journeys, magenta participant journeys, Excel bulk registration, organiser approval, personal dashboards, QR passes and daily check-in.

## Run locally

Requires Node.js 20 or newer.

```bash
npm install
npm run dev
```

Without environment variables the app starts in **local demo mode** and stores data in the browser. Any email/password combination can be used. Sign in as `admin@techpulse.test` to exercise organiser approval and check-in.

## Connect Supabase

1. Copy `.env.example` to `.env.local` and add the existing Supabase project URL and publishable key.
2. Install the Supabase CLI and start Docker Desktop for local database development.
3. Apply `supabase/migrations/202611210001_techpulse_portal.sql` to the dedicated project.
4. Create an account through the site, then bootstrap its organiser role using the commented SQL statement at the bottom of the migration.
5. In Supabase Auth, set the production Site URL and allow the GitHub Pages URL as a redirect. Enable email confirmations and configure custom SMTP before launch.

Only the Supabase publishable key belongs in frontend environment variables. Never expose a service-role key.

## Commands

```bash
npm test          # domain validation tests
npm run build     # type-check and create dist/
npm run preview   # serve the production build locally
```

The Vite build uses relative asset URLs, so `dist/` works at the repository path on GitHub Pages. The build script copies the existing image and video library into the output.

## Main workflows

- Visitor and participant single registration
- Per-competition participant teams
- Visitor/participant Excel templates, validation and atomic batch submission
- Email/password signup, verification and password recovery
- Optional student claims for coordinator-created registrations
- Organiser approval/rejection/revocation
- Approval-gated QR entry passes
- Camera/manual check-in once per festival day
- Supabase row-level ownership, staff roles and audit records

Existing Google Apps Script files remain in the repository as a legacy archive. The redesigned portal uses Supabase as its source of truth and does not import browser-local or Google Sheets records automatically.
