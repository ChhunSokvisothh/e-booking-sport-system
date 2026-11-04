
from django.contrib import admin
from django.urls import include, path

from features.auth.api.telegram import (
    telegram_start,
    telegram_status,
    telegram_webhook,
    telegram_link_start,
    telegram_link_status,
)

urlpatterns = [
    # Telegram authentication
    path(
        'api/auth/telegram/start/',
        telegram_start,
        name='telegram-auth-start',
    ),
    path(
        'api/auth/telegram/status/',
        telegram_status,
        name='telegram-auth-status',
    ),

    # Telegram account linking
    path(
        'api/auth/telegram/link/start/',
        telegram_link_start,
        name='telegram-link-start',
    ),
    path(
        'api/auth/telegram/link/status/',
        telegram_link_status,
        name='telegram-link-status',
    ),

    # Telegram bot webhook
    path(
        'api/auth/telegram/webhook/',
        telegram_webhook,
        name='telegram-auth-webhook',
    ),

    path('admin/', admin.site.urls),
    path('', include('core.urls')),
]
