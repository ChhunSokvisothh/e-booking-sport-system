from datetime import timedelta
import secrets
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from core.models import TelegramIdentity, TelegramLoginAttempt
from features.auth.api.telegram import _code_hash

User = get_user_model()


@override_settings(TELEGRAM_BOT_TOKEN='test-bot-token', TELEGRAM_WEBHOOK_SECRET='test-webhook-secret')
class TelegramAuthTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.webhook_url = '/api/auth/telegram/webhook'

    def _create_code(self, expires_at=None):
        code = f'one-time-test-code-{secrets.token_hex(4)}'
        attempt = TelegramLoginAttempt.objects.create(
            token_hash=_code_hash(code),
            expires_at=expires_at or timezone.now() + timedelta(minutes=5),
        )
        return code, attempt

    def _update(self, code, telegram_id=987654321):
        return {
            'update_id': 1234,
            'message': {
                'chat': {'id': telegram_id},
                'from': {'id': telegram_id, 'username': 'tester', 'first_name': 'Test'},
                'text': f'/start {code}',
            },
        }

    def _post_webhook(self, payload, secret='test-webhook-secret'):
        headers = {}
        if secret is not None:
            headers['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] = secret
        return self.client.post(self.webhook_url, payload, format='json', **headers)

    @patch('features.auth.api.telegram.requests.post')
    def test_wrong_or_missing_secret_is_forbidden(self, send_message):
        response = self.client.post(self.webhook_url, {}, format='json')
        self.assertEqual(response.status_code, 403)
        response = self._post_webhook({}, secret='incorrect')
        self.assertEqual(response.status_code, 403)
        send_message.assert_not_called()

    @patch('features.auth.api.telegram.requests.post')
    def test_first_sign_in_creates_blank_email_user_and_stores_only_hash(self, send_message):
        code, attempt = self._create_code()
        response = self._post_webhook(self._update(code))
        self.assertEqual(response.status_code, 200)
        user = User.objects.get(username='telegram_987654321')
        self.assertEqual(user.email, '')
        identity = TelegramIdentity.objects.get(telegram_user_id=987654321)
        self.assertEqual(identity.user, user)
        attempt.refresh_from_db()
        self.assertEqual(attempt.token_hash, _code_hash(code))
        self.assertNotEqual(attempt.token_hash, code)
        self.assertTrue(attempt.used)
        self.assertEqual(attempt.status, 'done')
        send_message.assert_called_once()

    @patch('features.auth.api.telegram.requests.post')
    def test_second_sign_in_reuses_existing_user(self, send_message):
        code, _ = self._create_code()
        self._post_webhook(self._update(code))
        original_user = TelegramIdentity.objects.get(telegram_user_id=987654321).user
        code, _ = self._create_code()
        response = self._post_webhook(self._update(code))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(User.objects.filter(username='telegram_987654321').count(), 1)
        self.assertEqual(TelegramIdentity.objects.get(telegram_user_id=987654321).user, original_user)
        self.assertEqual(send_message.call_count, 2)

    @patch('features.auth.api.telegram.requests.post')
    def test_expired_code_is_rejected(self, send_message):
        code, _ = self._create_code(expires_at=timezone.now() - timedelta(seconds=1))
        response = self._post_webhook(self._update(code))
        self.assertEqual(response.status_code, 200)
        self.assertFalse(TelegramIdentity.objects.exists())
        send_message.assert_called_once()
        self.assertIn('invalid or expired', send_message.call_args.kwargs['json']['text'])

    @patch('features.auth.api.telegram.requests.post')
    def test_reused_code_is_rejected_without_duplicate_account(self, send_message):
        code, _ = self._create_code()
        self._post_webhook(self._update(code))
        response = self._post_webhook(self._update(code))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(User.objects.filter(username='telegram_987654321').count(), 1)
        self.assertEqual(TelegramIdentity.objects.count(), 1)
        self.assertEqual(send_message.call_count, 2)

    def test_malformed_update_returns_ok(self):
        response = self.client.generic(
            'POST', self.webhook_url, data=b'{', content_type='application/json',
            HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN='test-webhook-secret',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'ok': True})

    @patch('features.auth.api.telegram.requests.post')
    def test_status_returns_session_token_only_after_confirmation(self, send_message):
        code, attempt = self._create_code()
        response = self.client.post('/api/auth/telegram/status', {'token': code})
        self.assertEqual(response.json(), {'status': 'pending'})
        self.assertNotIn('session', response.json())

        self._post_webhook(self._update(code))
        response = self.client.post('/api/auth/telegram/status', {'token': code})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['status'], 'done')
        session = response.json()['session']
        self.assertTrue(session['token'])
        self.assertEqual(session['email'], '')
        self.assertEqual(session['user_id'], TelegramIdentity.objects.get(telegram_user_id=987654321).user_id)
        self.assertEqual(response.json()['status'], 'done')
        attempt.refresh_from_db()
        self.assertEqual(attempt.status, 'exchanged')
        self.assertEqual(self.client.post('/api/auth/telegram/status', {'token': code}).status_code, 404)
        send_message.assert_called_once()
