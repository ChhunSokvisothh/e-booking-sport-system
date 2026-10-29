# Telegram account registration and sign-in

The Telegram button in the app opens @SportsSystemBot with a short-lived, single-use code. On the first successful attempt, the backend creates an app account and links it to the Telegram user ID. Later attempts sign in to that same account. Telegram does not provide a verified email, so Telegram-created accounts have a blank email and sign in through Telegram.

## Configure the backend

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token. If a token has been shared in a screenshot or chat, revoke it with BotFather and use the replacement.
2. Set these environment variables on the backend host:
2
   - `TELEGRAM_BOT_TOKEN`: token from BotFather.
   - `TELEGRAM_WEBHOOK_SECRET`: a random secret containing only letters, numbers, underscores, or hyphens. Telegram accepts 1 to 256 characters.

3. Deploy the backend and apply migrations with `python manage.py migrate`.
4. Register the webhook over HTTPS. Replace the placeholders and send this form to Telegram's Bot API `setWebhook` method:

   - `url`: `https://YOUR_BACKEND_HOST/api/auth/telegram/webhook`
   - `secret_token`: the same value as `TELEGRAM_WEBHOOK_SECRET`

   For example, use an HTTP POST to `https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook` with `url` and `secret_token` as form fields. Keep the bot token private.

## Configure the Flutter app

Build with the backend origin (for example `https://YOUR_BACKEND_HOST`) and bot username:

```sh
flutter build apk --dart-define=BACKEND_URL=https://YOUR_BACKEND_HOST --dart-define=TELEGRAM_BOT_USERNAME=SportsSystemBot
```

Do not include `@` in the username. For local development, Telegram still needs to reach the backend webhook over a public HTTPS URL.
