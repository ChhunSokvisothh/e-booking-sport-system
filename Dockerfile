FROM ghcr.io/cirruslabs/flutter:stable AS build

ARG BACKEND_URL=http://localhost:8000
ARG SUPABASE_URL=
ARG SUPABASE_ANON_KEY=

WORKDIR /workspace
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nBACKEND_URL=%s\n' \
        "$SUPABASE_URL" "$SUPABASE_ANON_KEY" "$BACKEND_URL" > .env \
    && flutter build web --release

FROM nginx:1.29-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/build/web /usr/share/nginx/html

EXPOSE 80
