FROM ghcr.io/cirruslabs/flutter:stable AS build

ARG BACKEND_URL=http://localhost:8000
ARG SUPABASE_URL=
ARG SUPABASE_ANON_KEY=

WORKDIR /workspace
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
    --dart-define=BACKEND_URL="$BACKEND_URL" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

FROM nginx:1.29-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/build/web /usr/share/nginx/html

EXPOSE 80
