from django.conf import settings
from supabase import create_client

BUCKET = 'profile-photos'
SIGNED_URL_EXPIRY_SECONDS = 60 * 60 * 24


def _storage():
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError('Supabase Storage server credentials are not configured.')

    client = create_client(
        settings.SUPABASE_URL,
        settings.SUPABASE_SERVICE_ROLE_KEY,
    )
    return client.storage.from_(BUCKET)


def create_upload_permission(path):
    result = _storage().create_signed_upload_url(path)
    if not isinstance(result, dict):
        result = result.model_dump() if hasattr(result, 'model_dump') else vars(result)

    token = result.get('token')
    if not token:
        raise RuntimeError('Supabase did not return a signed upload token.')
    return token


def create_download_url(path):
    result = _storage().create_signed_url(path, SIGNED_URL_EXPIRY_SECONDS)
    if not isinstance(result, dict):
        result = result.model_dump() if hasattr(result, 'model_dump') else vars(result)

    signed_url = result.get('signedURL') or result.get('signedUrl')
    if not signed_url:
        raise RuntimeError('Supabase did not return a signed download URL.')

    if signed_url.startswith('https://') or signed_url.startswith('http://'):
        return signed_url

    base_url = settings.SUPABASE_URL.rstrip('/')
    if signed_url.startswith('/storage/v1/'):
        return f'{base_url}{signed_url}'
    return f'{base_url}/storage/v1{signed_url if signed_url.startswith("/") else "/" + signed_url}'


def avatar_exists(path):
    # info() is a server-side metadata lookup; the service-role key never leaves Django.
    result = _storage().info(path)
    if isinstance(result, dict):
        return result
    if hasattr(result, 'model_dump'):
        return result.model_dump()
    return vars(result)


def delete_avatar(path):
    if path:
        _storage().remove([path])
