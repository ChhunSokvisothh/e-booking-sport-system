from django.contrib import admin
from django.urls import include, path
from features.auth.api.telegram import telegram_start, telegram_status, telegram_webhook

urlpatterns = [
    path('api/auth/telegram/start', telegram_start, name='telegram-auth-start'),
    path('api/auth/telegram/status', telegram_status, name='telegram-auth-status'),
    path('api/auth/telegram/webhook', telegram_webhook, name='telegram-auth-webhook'),
    path('admin/', admin.site.urls),
    path('', include('core.urls')),
]
