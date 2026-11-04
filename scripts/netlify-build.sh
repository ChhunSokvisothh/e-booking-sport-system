
#!/usr/bin/env bash
set -e

: "${BACKEND_URL:?Missing BACKEND_URL}"
: "${SUPABASE_URL:?Missing SUPABASE_URL}"
: "${SUPABASE_ANON_KEY:?Missing SUPABASE_ANON_KEY}"

flutter build web --release \
  --dart-define=BACKEND_URL="$BACKEND_URL" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
