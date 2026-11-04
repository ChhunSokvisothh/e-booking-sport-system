
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
flutter build web --release \
  --dart-define=API_BASE_URL=https://e-booking-sport-system.onrender.com

echo "Build completed successfully."
