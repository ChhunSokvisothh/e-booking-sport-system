# Telegram account registration and sign-in

The Telegram button in the app opens @SportsSystemBot with a short-lived, single-use code. On the first successful attempt, the backend creates an app account and links it to the Telegram user ID. Later attempts sign in to that same account. Telegram does not provide a verified email, so Telegram-created accounts have a blank email and sign in through Telegram.

## Configure the backend

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token. If a token has been shared in a screenshot or chat, revoke it with BotFather and use the replacement.
2. Set these environment variables on the backend host:
2
   - `TELEGRAM_BOT_TOKEN`: token from BotFather.
   - `TELEGRAM_WEBHOOK_SECRET`: a random secret containing only letters, numbers, underscores, or hyphens. Telegram accepts 1 to 256 characters.
   - `TELEGRAM_WEBHOOK_URL`: the public HTTPS webhook URL, for example `https://YOUR_BACKEND_HOST/api/auth/telegram/webhook`.

3. Deploy the backend. Its container startup applies migrations and registers the webhook using `TELEGRAM_WEBHOOK_URL` and `TELEGRAM_WEBHOOK_SECRET`.
4. If you change the webhook secret or URL, update the backend environment values and redeploy. The startup command will register the new webhook with Telegram. Keep the bot token private.

## Configure the Flutter app

Build with the backend origin (for example `https://YOUR_BACKEND_HOST`) and bot username:

```sh
flutter build apk --dart-define=BACKEND_URL=https://YOUR_BACKEND_HOST --dart-define=TELEGRAM_BOT_USERNAME=SportsSystemBot
```

Do not include `@` in the username. For local development, Telegram still needs to reach the backend webhook over a public HTTPS URL.
