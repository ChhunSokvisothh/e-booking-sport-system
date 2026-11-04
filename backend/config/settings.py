import os
from pathlib import Path

from dotenv import load_dotenv
import dj_database_url


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / '.env')


# ==============================================================================
# CORE SETTINGS
# ==============================================================================

SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret')

DEBUG = os.getenv('DEBUG', 'False').lower() in ['1', 'true', 'yes']

BACKEND_URL = 'https://e-booking-sport-system.onrender.com'
BACKEND_HOST = 'e-booking-sport-system.onrender.com'
TELEGRAM_WEBHOOK_URL = (
    f'{BACKEND_URL}/api/auth/telegram/webhook/'
)

ALLOWED_HOSTS = [
    '127.0.0.1',
    'localhost',
    BACKEND_HOST,
]


# ==============================================================================
# INSTALLED APPS
# ==============================================================================

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Third-party packages
    'corsheaders',
    'rest_framework',
    'rest_framework.authtoken',

    # Local apps
    'core',
]


# ==============================================================================
# MIDDLEWARE
# ==============================================================================

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]


ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'


# ==============================================================================
# DATABASE CONFIGURATION
# ==============================================================================

DATABASES = {
    'default': dj_database_url.parse(
        os.environ['DATABASE_URL'],
        conn_max_age=60,
        ssl_require=True,
    )
}

DATABASES['default']['CONN_HEALTH_CHECKS'] = True


# ==============================================================================
# INTERNATIONALIZATION
# ==============================================================================

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True


# ==============================================================================
# STATIC FILES
# ==============================================================================

STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

STATICFILES_STORAGE = (
    'whitenoise.storage.CompressedManifestStaticFilesStorage'
)

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# ==============================================================================
# CORS & SECURITY
# ==============================================================================

CORS_ALLOW_ALL_ORIGINS = (
    os.getenv('CORS_ALLOW_ALL_ORIGINS', 'False').lower()
    in ['1', 'true', 'yes']
)

if not CORS_ALLOW_ALL_ORIGINS:
    CORS_ALLOWED_ORIGINS = [
        origin.strip()
        for origin in os.getenv(
            'CORS_ALLOWED_ORIGINS',
            'http://localhost:3000,http://127.0.0.1:3000'
        ).split(',')
        if origin.strip()
    ]

    FRONTEND_URL = 'https://e-booking-sports.netlify.app'

    if FRONTEND_URL not in CORS_ALLOWED_ORIGINS:
        CORS_ALLOWED_ORIGINS.append(FRONTEND_URL)

    CORS_ALLOWED_ORIGIN_REGEXES = [
        r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$',
    ]


CSRF_TRUSTED_ORIGINS = [
    BACKEND_URL,
    'https://e-booking-sports.netlify.app',
]


# ==============================================================================
# DJANGO REST FRAMEWORK
# ==============================================================================

REST_FRAMEWORK = {
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.AllowAny',
    ],
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.TokenAuthentication',
    ],
    'DEFAULT_PAGINATION_CLASS': (
        'rest_framework.pagination.PageNumberPagination'
    ),
    'PAGE_SIZE': 12,
}


# ==============================================================================
# CACHE
# ==============================================================================

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'e_booking_cache',
    }
}


# ==============================================================================
# SUPABASE CONFIGURATION
# ==============================================================================

SUPABASE_URL = os.getenv('SUPABASE_URL', '')
SUPABASE_SERVICE_ROLE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY', '')

SUPABASE_BOOKING_TABLE = os.getenv(
    'SUPABASE_BOOKING_TABLE',
    'core_booking'
)

SUPABASE_TIMESLOT_TABLE = os.getenv(
    'SUPABASE_TIMESLOT_TABLE',
    'core_timeslot'
)


# ==============================================================================
# AI / THIRD-PARTY SERVICES
# ==============================================================================

GROQ_API_KEY = os.getenv('GROQ_API_KEY', '')
HF_API_KEY = os.getenv('HF_API_KEY', '')


# ==============================================================================
# TELEGRAM CONFIGURATION
# ==============================================================================

TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_BOT_USERNAME = os.getenv('TELEGRAM_BOT_USERNAME', '')

TELEGRAM_WEBHOOK_SECRET = os.getenv(
    'TELEGRAM_WEBHOOK_SECRET',
    ''
)

# Always use the single canonical backend URL.
TELEGRAM_WEBHOOK_URL = (
    f'{BACKEND_URL}/api/auth/telegram/webhook/'
)