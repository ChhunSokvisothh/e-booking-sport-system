
#!/usr/bin/env bash
set -euo pipefail

echo "Installing Flutter 3.47.5..."

git clone --depth 1 --branch 3.47.5 \
  https://github.com/flutter/flutter.git \
  "$HOME/flutter"

export PATH="$HOME/flutter/bin:$PATH"

flutter config --no-analytics
flutter precache --web

echo "Flutter version:"
flutter --version

echo "Installing dependencies..."
flutter pub get

echo "Building Flutter web..."

: "${BACKEND_URL:?Missing BACKEND_URL}"
: "${SUPABASE_URL:?Missing SUPABASE_URL}"
: "${SUPABASE_ANON_KEY:?Missing SUPABASE_ANON_KEY}"

flutter build web --release \
  --dart-define=BACKEND_URL="$BACKEND_URL" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo "Build completed successfully."
