import requests
from django.conf import settings
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Register the configured Telegram webhook with Telegram.'

    def handle(self, *args, **options):
        token = (settings.TELEGRAM_BOT_TOKEN or '').strip()
        secret = (settings.TELEGRAM_WEBHOOK_SECRET or '').strip()
        webhook_url = (getattr(settings, 'TELEGRAM_WEBHOOK_URL', '') or '').strip()

        if not token or not secret or not webhook_url:
            self.stdout.write('Telegram webhook settings incomplete; skipping registration.')
            return

        try:
            response = requests.post(
                f'https://api.telegram.org/bot{token}/setWebhook',
                data={'url': webhook_url, 'secret_token': secret},
                timeout=20,
            )
            result = response.json()
        except (requests.RequestException, ValueError):
            self.stderr.write('Telegram webhook registration request failed.')
            return

        if response.ok and result.get('ok'):
            self.stdout.write('Telegram webhook registered.')
            return

        description = result.get('description', 'Telegram rejected the webhook configuration.')
        self.stderr.write(f'Telegram webhook registration failed: {description}')
