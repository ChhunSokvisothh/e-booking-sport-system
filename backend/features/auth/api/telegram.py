import hashlib
import hmac
import json
import secrets
from datetime import timedelta

import requests
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.authtoken.models import Token

from core.models import TelegramIdentity, TelegramLoginAttempt
from global_utils.view_helpers import _role_for_user, _uuid_from_user

User = get_user_model()
LOGIN_CODE_LIFETIME = timedelta(minutes=5)


def _code_hash(code):
    return hashlib.sha256(code.encode('utf-8')).hexdigest()


@api_view(['POST'])
@permission_classes([AllowAny])
def telegram_start(request):
    if not settings.TELEGRAM_BOT_TOKEN:
        return Response({'error': 'Telegram login is not configured.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
    code = secrets.token_urlsafe(32)
    TelegramLoginAttempt.objects.create(
        token_hash=_code_hash(code),
        expires_at=timezone.now() + LOGIN_CODE_LIFETIME,
    )
    return Response({'token': code, 'expires_in': int(LOGIN_CODE_LIFETIME.total_seconds())}, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([AllowAny])
def telegram_status(request):
    code = request.data.get('token', '')
    if not code:
        return Response({'status': 'error'}, status=status.HTTP_404_NOT_FOUND)
    try:
        with transaction.atomic():
            attempt = TelegramLoginAttempt.objects.select_for_update().select_related('user').get(token_hash=_code_hash(code))
            if attempt.expires_at <= timezone.now():
                attempt.delete()
                return Response({'status': 'expired'})
            if attempt.status == 'exchanged':
                return Response({'status': 'error'}, status=status.HTTP_404_NOT_FOUND)
            if attempt.status != 'done' or not attempt.used or not attempt.user_id:
                return Response({'status': 'pending'})

            user = attempt.user
            token_obj, _ = Token.objects.get_or_create(user=user)
            session = {
                'token': token_obj.key,
                'user_id': user.id,
                'user_uuid': str(_uuid_from_user(user)),
                'email': user.email,
                'role': _role_for_user(user),
            }
            exchanged = TelegramLoginAttempt.objects.filter(
                pk=attempt.pk,
                status='done',
                used=True,
            ).update(status='exchanged')
            if not exchanged:
                return Response({'status': 'error'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'status': 'done', 'session': session})
    except TelegramLoginAttempt.DoesNotExist:
        return Response({'status': 'error'}, status=status.HTTP_404_NOT_FOUND)


def _telegram_send_message(chat_id, text):
    if not settings.TELEGRAM_BOT_TOKEN or not chat_id:
        return
    try:
        requests.post(
            f'https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage',
            json={'chat_id': chat_id, 'text': text},
            timeout=2,
        ).raise_for_status()
    except requests.RequestException:
        pass


@api_view(['POST'])
@permission_classes([AllowAny])
def telegram_webhook(request):
    expected_secret = settings.TELEGRAM_WEBHOOK_SECRET
    supplied_secret = request.headers.get('X-Telegram-Bot-Api-Secret-Token', '')
    if not expected_secret or not hmac.compare_digest(supplied_secret, expected_secret):
        return HttpResponse(status=403)

    try:
        update = json.loads(request.body or b'{}')
    except (json.JSONDecodeError, UnicodeDecodeError):
        return Response({'ok': True})
    if not isinstance(update, dict):
        return Response({'ok': True})
    message = update.get('message') or {}
    if not isinstance(message, dict):
        return Response({'ok': True})
    chat = message.get('chat') or {}
    telegram_user = message.get('from') or {}
    if not isinstance(chat, dict) or not isinstance(telegram_user, dict):
        return Response({'ok': True})
    chat_id = chat.get('id')
    text = message.get('text')
    if not isinstance(text, str):
        return Response({'ok': True})
    parts = text.strip().split(maxsplit=1)
    if not parts or parts[0].split('@', 1)[0] != '/start':
        return Response({'ok': True})
    if len(parts) != 2 or not isinstance(telegram_user.get('id'), int):
        _telegram_send_message(chat_id, 'This sign-in code is invalid or expired. Please start again from the e-Booking app.')
        return Response({'ok': True})

    code_hash = _code_hash(parts[1].strip())
    telegram_id = telegram_user['id']
    now = timezone.now()
    success = False
    try:
        with transaction.atomic():
            attempt = TelegramLoginAttempt.objects.filter(
                token_hash=code_hash,
                status='pending',
                used=False,
                expires_at__gt=now,
            ).first()
            if attempt:
                consumed = TelegramLoginAttempt.objects.filter(
                    pk=attempt.pk,
                    status='pending',
                    used=False,
                    expires_at__gt=now,
                ).update(used=True)
                if consumed:
                    identity = TelegramIdentity.objects.select_related('user').filter(telegram_user_id=telegram_id).first()
                    if identity:
                        user = identity.user
                        identity.username = telegram_user.get('username') or ''
                        identity.first_name = telegram_user.get('first_name') or ''
                        identity.save(update_fields=['username', 'first_name'])
                    else:
                        user = User.objects.create_user(username=f'telegram_{telegram_id}', email='')
                        TelegramIdentity.objects.create(
                            telegram_user_id=telegram_id,
                            user=user,
                            username=telegram_user.get('username') or '',
                            first_name=telegram_user.get('first_name') or '',
                        )
                    TelegramLoginAttempt.objects.filter(pk=attempt.pk).update(status='done', user=user)
                    success = True
    except Exception:
        # Telegram retries failed updates. Returning 200 avoids retry storms;
        # the user can request a fresh code if the database transaction rolled back.
        return Response({'ok': True})

    if success:
        _telegram_send_message(chat_id, 'Signed in. Return to the e-Booking app.')
    else:
        _telegram_send_message(chat_id, 'This sign-in code is invalid or expired. Please start again from the e-Booking app.')
    return Response({'ok': True})
