
import hashlib
import hmac
import logging
import secrets
from datetime import timedelta

import requests

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.authtoken.models import Token

from core.models import (
    TelegramIdentity,
    TelegramLoginAttempt,
    TelegramLinkAttempt,
)
from global_utils.view_helpers import _role_for_user, _uuid_from_user

logger = logging.getLogger(__name__)
User = get_user_model()

TOKEN_LIFETIME = timedelta(minutes=5)


def _hash_code(code):
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _generate_code():
    return secrets.token_urlsafe(32)


def _telegram_send_message(chat_id, message):
    if not settings.TELEGRAM_BOT_TOKEN:
        logger.error("TELEGRAM_BOT_TOKEN is not configured.")
        return

    url = (
        f"https://api.telegram.org/bot"
        f"{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    )

    try:
        response = requests.post(
            url,
            json={
                "chat_id": chat_id,
                "text": message,
            },
            timeout=10,
        )
        response.raise_for_status()
    except requests.RequestException:
        logger.exception("Failed to send Telegram message.")


def _auth_payload(user):
    token, _ = Token.objects.get_or_create(user=user)

    return {
        "token": token.key,
        "user_id": user.id,
        "user_uuid": str(_uuid_from_user(user)),
        "email": user.email,
        "role": _role_for_user(user),
    }


# ============================================================
# TELEGRAM LOGIN
# ============================================================

@api_view(["POST"])
@permission_classes([AllowAny])
def telegram_start(request):
    """
    Create a temporary Telegram login attempt.

    The frontend opens the returned Telegram URL.
    The user presses Start in the bot.
    """

    if not settings.TELEGRAM_BOT_USERNAME:
        return Response(
            {"error": "Telegram bot username is not configured."},
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    code = _generate_code()

    TelegramLoginAttempt.objects.create(
        token_hash=_hash_code(code),
        status="pending",
        expires_at=timezone.now() + TOKEN_LIFETIME,
    )

    return Response({
        "telegram_url": (
            f"https://t.me/{settings.TELEGRAM_BOT_USERNAME}"
            f"?start={code}"
        ),
        "expires_in": 300,
    })


@api_view(["POST"])
@permission_classes([AllowAny])
def telegram_status(request):
    """
    Exchange a completed Telegram login code for a Django token.
    The code can only be exchanged once.
    """

    code = (request.data.get("code") or "").strip()

    if not code:
        return Response(
            {"error": "code is required"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    with transaction.atomic():
        attempt = (
            TelegramLoginAttempt.objects
            .select_for_update()
            .filter(token_hash=_hash_code(code))
            .first()
        )

        if not attempt:
            return Response(
                {"error": "Invalid login code."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if attempt.expires_at <= timezone.now():
            attempt.status = "expired"
            attempt.save(update_fields=["status"])

            return Response(
                {"error": "Login code expired. Try again."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if attempt.used or attempt.status == "exchanged":
            return Response(
                {"error": "This login code has already been used."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if attempt.status != "done" or not attempt.user_id:
            return Response({
                "status": "pending",
                "message": "Waiting for Telegram confirmation.",
            })

        user = attempt.user
        attempt.used = True
        attempt.status = "exchanged"
        attempt.save(update_fields=["used", "status"])

    return Response({
        "status": "authenticated",
        **_auth_payload(user),
    })


# ============================================================
# TELEGRAM ACCOUNT LINKING
# ============================================================

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def telegram_link_start(request):
    """
    Create a temporary link code for the currently authenticated user.
    """

    if not settings.TELEGRAM_BOT_USERNAME:
        return Response(
            {"error": "Telegram bot username is not configured."},
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    existing = TelegramIdentity.objects.filter(
        user=request.user
    ).first()

    if existing:
        return Response(
            {
                "error": "A Telegram account is already linked.",
                "telegram_username": existing.username,
            },
            status=status.HTTP_409_CONFLICT,
        )

    code = _generate_code()

    TelegramLinkAttempt.objects.create(
        token_hash=_hash_code(code),
        user=request.user,
        expires_at=timezone.now() + TOKEN_LIFETIME,
    )

    return Response({
        "telegram_url": (
            f"https://t.me/{settings.TELEGRAM_BOT_USERNAME}"
            f"?start={code}"
        ),
        "expires_in": 300,
    })


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def telegram_link_status(request):
    identity = TelegramIdentity.objects.filter(
        user=request.user
    ).first()

    if not identity:
        return Response({
            "linked": False,
        })

    return Response({
        "linked": True,
        "telegram_username": identity.username,
        "telegram_first_name": identity.first_name,
        "linked_at": identity.linked_at,
    })


def _handle_link_attempt(code, telegram_user):
    """
    Attach a Telegram identity to the existing authenticated account.

    Never transfer a Telegram identity between users.
    """

    with transaction.atomic():
        attempt = (
            TelegramLinkAttempt.objects
            .select_for_update()
            .filter(token_hash=_hash_code(code))
            .first()
        )

        if not attempt or attempt.used:
            return "invalid"

        if attempt.expires_at <= timezone.now():
            attempt.used = True
            attempt.save(update_fields=["used"])
            return "expired"

        telegram_id = telegram_user["id"]

        # A Telegram identity must belong to only one Django user.
        identity = TelegramIdentity.objects.filter(
            telegram_user_id=telegram_id
        ).first()

        if identity and identity.user_id != attempt.user_id:
            attempt.used = True
            attempt.save(update_fields=["used"])
            return "already_linked"

        if not identity:
            try:
                # Nested atomic creates a savepoint. This lets us safely
                # handle a concurrent attempt to claim the same Telegram ID.
                with transaction.atomic():
                    TelegramIdentity.objects.create(
                        telegram_user_id=telegram_id,
                        user=attempt.user,
                        username=telegram_user.get("username", "") or "",
                        first_name=telegram_user.get("first_name", "") or "",
                    )
            except IntegrityError:
                identity = TelegramIdentity.objects.filter(
                    telegram_user_id=telegram_id
                ).first()

                if not identity or identity.user_id != attempt.user_id:
                    attempt.used = True
                    attempt.save(update_fields=["used"])
                    return "already_linked"

        else:
            identity.username = telegram_user.get("username", "") or ""
            identity.first_name = telegram_user.get("first_name", "") or ""
            identity.save(update_fields=["username", "first_name"])

        attempt.used = True
        attempt.save(update_fields=["used"])

    return "linked"


# ============================================================
# TELEGRAM WEBHOOK
# ============================================================

@csrf_exempt
@require_POST
def telegram_webhook(request):
    """
    Telegram sends /start <code> here.

    The code is checked against:
      1. TelegramLinkAttempt -> attach Telegram to existing user.
      2. TelegramLoginAttempt -> authenticate an already-linked user.
    """

    expected_secret = settings.TELEGRAM_WEBHOOK_SECRET
    received_secret = request.headers.get(
        "X-Telegram-Bot-Api-Secret-Token", ""
    )

    if (
        not expected_secret
        or not hmac.compare_digest(received_secret, expected_secret)
    ):
        return JsonResponse(
            {"error": "Unauthorized"},
            status=401,
        )

    try:
        import json
        payload = json.loads(request.body or b"{}")

        message = payload.get("message") or {}
        chat = message.get("chat") or {}
        telegram_user = message.get("from") or {}

        text = (message.get("text") or "").strip()
        chat_id = chat.get("id")

        if not chat_id or not telegram_user.get("id"):
            return JsonResponse({"ok": True})

        if not text.startswith("/start"):
            _telegram_send_message(
                chat_id,
                "Welcome to E-Booking Sport! "
                "Use the login or account-linking option in the app "
                "to connect your Telegram account.",
            )
            return JsonResponse({"ok": True})

        parts = text.split(maxsplit=1)

        if len(parts) < 2:
            _telegram_send_message(
                chat_id,
                "Open Telegram from the E-Booking Sport app to continue.",
            )
            return JsonResponse({"ok": True})

        code = parts[1].strip()

        if len(code) > 200:
            return JsonResponse({"ok": True})

        # ----------------------------------------------------
        # FIRST: Check if this is an account-linking attempt.
        # ----------------------------------------------------

        link_attempt_exists = TelegramLinkAttempt.objects.filter(
            token_hash=_hash_code(code)
        ).exists()

        if link_attempt_exists:
            result = _handle_link_attempt(code, telegram_user)

            messages = {
                "linked": (
                    "Your Telegram account has been successfully linked "
                    "to your E-Booking Sport account. You can now log in "
                    "through Telegram."
                ),
                "already_linked": (
                    "This Telegram account is already linked to another "
                    "E-Booking Sport account. It cannot be transferred."
                ),
                "expired": (
                    "This linking code has expired. Please generate "
                    "a new one in Account Settings."
                ),
                "invalid": (
                    "This linking code is invalid or has already been used."
                ),
            }

            _telegram_send_message(
                chat_id,
                messages.get(result, "Unable to link your account."),
            )

            return JsonResponse({"ok": True})

        # ----------------------------------------------------
        # SECOND: Check if this is a login attempt.
        # ----------------------------------------------------

        with transaction.atomic():
            attempt = (
                TelegramLoginAttempt.objects
                .select_for_update()
                .filter(token_hash=_hash_code(code))
                .first()
            )

            if (
                not attempt
                or attempt.used
                or attempt.status != "pending"
                or attempt.expires_at <= timezone.now()
            ):
                if attempt and attempt.expires_at <= timezone.now():
                    attempt.status = "expired"
                    attempt.save(update_fields=["status"])

                login_result = "invalid"

            else:
                identity = TelegramIdentity.objects.filter(
                    telegram_user_id=telegram_user["id"]
                ).first()

                if not identity:
                    login_result = "not_linked"
                else:
                    attempt.user = identity.user
                    attempt.status = "done"
                    attempt.save(update_fields=["user", "status"])
                    login_result = "done"

        if login_result == "done":
            _telegram_send_message(
                chat_id,
                "Login confirmed! Return to E-Booking Sport to finish "
                "signing in.",
            )

        elif login_result == "not_linked":
            _telegram_send_message(
                chat_id,
                "This Telegram account is not linked to an E-Booking Sport "
                "account yet. Please sign in using your email and password, "
                "then go to Account Settings → Link Telegram.",
            )

        else:
            _telegram_send_message(
                chat_id,
                "This login code is invalid, expired, or already used. "
                "Please try again from the app.",
            )

        return JsonResponse({"ok": True})

    except Exception:
        logger.exception("Telegram webhook processing failed.")
        return JsonResponse({"ok": True})
