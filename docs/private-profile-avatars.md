# Private profile avatars

The profile photo flow uses Flutter, Django Token Authentication, Supabase Storage, and the existing PostgreSQL-backed `UserProfile`.

## Storage setup

Run `backend/sql/profile_photos_private_bucket.sql` in the Supabase SQL Editor. The bucket must remain private.

No public read policy is required. Django uses the server-side Supabase service-role key to issue short-lived signed upload and download URLs. Flutter receives only a one-time upload token or a temporary signed download URL.

## Environment variables

### Render / Django backend

Set:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (server-side secret only)

### Netlify / Flutter web build

Set:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (publishable/anon client key)
- `BACKEND_URL`

The Netlify build script already passes these as Dart defines. Docker builds must pass the corresponding build args.

For local Flutter development, pass:
```powershell
flutter run -d chrome `
  --dart-define=BACKEND_URL=http://127.0.0.1:8000 `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

## API flow

1. Flutter requests `POST /api/auth/profile/avatar/upload-url/`.
2. Django creates a random object path under the authenticated user's numeric ID and returns a short-lived signed upload token.
3. Flutter uploads bytes to the private `profile-photos` bucket.
4. Flutter calls `POST /api/auth/profile/avatar/complete/`; Django checks ownership, object existence, MIME metadata and size, then saves `avatar_path` in PostgreSQL.
5. `GET /api/auth/profile/` returns a fresh 24-hour signed download URL as `avatar_url`.
6. `DELETE /api/auth/profile/avatar/` clears the database path and removes the old object.

The database stores the Storage object path, never an expiring signed URL.

## Migration note

The branch migration `0019_profile_venue_fields_and_telegram_link.py` includes the venue fields already present in `Facility`, the `UserProfile.avatar_path` field, and `TelegramLinkAttempt`.

If you generated the un-applied local migration `0019_facility_amenities_facility_cancellation_policy_and_more.py` before pulling this branch update, back it up and remove that duplicate generated migration before pulling. It overlaps with the committed migration and must not be applied alongside it. Your reported failure at migration 0016 means migration 0019 was not reached; verify this in `django_migrations` before removing any file.

Your existing `0016_favorite_facility` duplicate-table issue is separate. Confirm that `core_favoritefacility` matches migration 0016 before considering `python manage.py migrate core 0016 --fake`.
