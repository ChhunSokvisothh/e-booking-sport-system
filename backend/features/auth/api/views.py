
import re
import uuid
import logging
from decimal import Decimal, InvalidOperation

from django.db import IntegrityError, transaction

from django.contrib.auth import authenticate
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from global_utils.view_helpers import (
    User,
    _rate_limit_check,
    _role_for_user,
    _uuid_from_user,
)
from core.models import OwnerApplication, UserProfile
from .avatar_storage import (
    avatar_exists,
    create_download_url,
    create_upload_permission,
    delete_avatar,
)

def _auth_payload(user, token):
    owner_status = (
        OwnerApplication.objects
        .filter(user_id=user.id)
        .values_list('status', flat=True)
        .first()
    )
    return {
        'token': token.key,
        'user_id': user.id,
        'user_uuid': str(_uuid_from_user(user)),
        'email': user.email,
        'role': _role_for_user(user),
        'owner_status': owner_status,
        'is_superuser': bool(user.is_superuser),
    }

@api_view(['POST'])
@permission_classes([AllowAny])
def auth_signup(request):
    email = (request.data.get('email') or '').strip().lower()
    password = (request.data.get('password') or '').strip()

    if not email or not password:
        return Response({'error': 'email and password are required'}, status=status.HTTP_400_BAD_REQUEST)
    if len(password) < 8:
        return Response({'error': 'password must be at least 8 characters'}, status=status.HTTP_400_BAD_REQUEST)
    if User.objects.filter(username=email).exists():
        return Response({'error': 'email already registered'}, status=status.HTTP_409_CONFLICT)

    user = User.objects.create_user(username=email, email=email, password=password)
    token, _ = Token.objects.get_or_create(user=user)
    return Response(_auth_payload(user, token), status=status.HTTP_201_CREATED)


OWNER_REGISTRATION_FEE = Decimal('20.00')
OWNER_PAYMENT_METHODS = {
    'Bakong QR': 'local_bank',
    'ABA Bank': 'local_bank',
    'Visa': 'card',
    'Mastercard': 'card',
    'PayPal': 'international_bank',
}

@api_view(['POST'])
@permission_classes([AllowAny])
def owner_signup(request):
    """Create an owner account only after the simulated registration payment succeeds."""
    email = (request.data.get('email') or '').strip().lower()
    password = (request.data.get('password') or '').strip()
    venue_name = (request.data.get('venue_name') or '').strip()
    phone = (request.data.get('contact_phone') or '').strip()
    payment_provider = (request.data.get('payment_provider') or '').strip()
    payment_channel = (request.data.get('payment_channel') or '').strip().lower()
    try:
        paid_amount = Decimal(str(request.data.get('amount')))
    except (InvalidOperation, TypeError, ValueError):
        paid_amount = None

    if not email or not password or not venue_name:
        return Response({'error': 'email, password, and venue_name are required'}, status=status.HTTP_400_BAD_REQUEST)
    if len(password) < 8:
        return Response({'error': 'password must be at least 8 characters'}, status=status.HTTP_400_BAD_REQUEST)
    if User.objects.filter(username=email).exists():
        return Response({'error': 'email already registered'}, status=status.HTTP_409_CONFLICT)
    if OWNER_PAYMENT_METHODS.get(payment_provider) != payment_channel:
        return Response({'error': 'Choose a valid payment method to continue.'}, status=status.HTTP_400_BAD_REQUEST)
    if paid_amount != OWNER_REGISTRATION_FEE:
        return Response({'error': 'Owner registration payment must be exactly $20.00 USD.'}, status=status.HTTP_400_BAD_REQUEST)

    # This is deliberately a simulated payment for the prototype. A real gateway
    # must replace this client-triggered confirmation before production.
    try:
        with transaction.atomic():
            user = User.objects.create_user(username=email, email=email, password=password)
            OwnerApplication.objects.create(
                user=user,
                venue_name=venue_name,
                contact_phone=phone,
                status=OwnerApplication.Status.APPROVED,
                reviewed_at=timezone.now(),
            )
            token, _ = Token.objects.get_or_create(user=user)
    except IntegrityError:
        return Response({'error': 'email already registered'}, status=status.HTTP_409_CONFLICT)
    return Response({
        **_auth_payload(user, token),
        'message': 'Simulated owner registration payment successful.',
        'payment_status': 'mock_paid',
        'payment_provider': payment_provider,
        'payment_channel': payment_channel,
        'amount': str(OWNER_REGISTRATION_FEE),
        'currency': 'USD',
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([AllowAny])
def auth_login(request):
    email = (request.data.get('email') or '').strip().lower()
    password = (request.data.get('password') or '').strip()

    if not email or not password:
        return Response({'error': 'email and password are required'}, status=status.HTTP_400_BAD_REQUEST)
    if not _rate_limit_check(request, action='login', identifier=email):
        return Response(
            {'error': 'Too many login attempts. Please try again in a minute.'},
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    user = authenticate(username=email, password=password)
    if user is None:
        return Response({'error': 'invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)

    token, _ = Token.objects.get_or_create(user=user)
    return Response(_auth_payload(user, token))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def auth_logout(request):
    Token.objects.filter(user=request.user).delete()
    return Response({'ok': True})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def auth_me(request):
    owner_status = (
        OwnerApplication.objects
        .filter(user_id=request.user.id)
        .values_list('status', flat=True)
        .first()
    )
    return Response(
        {
            'user_id': request.user.id,
            'user_uuid': str(_uuid_from_user(request.user)),
            'email': request.user.email,
            'role': _role_for_user(request.user),
            'owner_status': owner_status,
            'is_superuser': bool(request.user.is_superuser),
            'venue_name': (
                OwnerApplication.objects.filter(user_id=request.user.id)
                .values_list('venue_name', flat=True).first()
            ),
            'contact_phone': (
                OwnerApplication.objects.filter(user_id=request.user.id)
                .values_list('contact_phone', flat=True).first()
            ),
        }
    )


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def auth_profile(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)

    if request.method == 'PATCH':
        allowed_fields = {
            'display_name': (str, 100),
            'preferred_city': (str, 100),
            'favorite_sport': (str, 32),
        }
        for field, (expected_type, max_length) in allowed_fields.items():
            if field in request.data:
                value = request.data[field]
                if not isinstance(value, expected_type):
                    return Response({'error': f'{field} must be text.'}, status=status.HTTP_400_BAD_REQUEST)
                value = value.strip()
                if len(value) > max_length:
                    return Response({'error': f'{field} must be {max_length} characters or fewer.'}, status=status.HTTP_400_BAD_REQUEST)
                setattr(profile, field, value)

        for field in ('push_notifications', 'special_offers'):
            if field in request.data:
                value = request.data[field]
                if not isinstance(value, bool):
                    return Response({'error': f'{field} must be true or false.'}, status=status.HTTP_400_BAD_REQUEST)
                setattr(profile, field, value)

        valid_sports = {'football', 'billiard', 'pickleball', 'volleyball', 'basketball', 'futsal', 'tennis', 'badminton'}
        if profile.favorite_sport and profile.favorite_sport.lower() not in valid_sports:
            return Response({'error': 'Choose a valid favorite sport.'}, status=status.HTTP_400_BAD_REQUEST)
        profile.save()

    avatar_url = None
    if profile.avatar_path:
        try:
            avatar_url = create_download_url(profile.avatar_path)
        except Exception:
            # Keep profile data available even if Storage is temporarily unavailable.
            avatar_url = None

    return Response({
        'display_name': profile.display_name,
        'preferred_city': profile.preferred_city,
        'favorite_sport': profile.favorite_sport,
        'push_notifications': profile.push_notifications,
        'special_offers': profile.special_offers,
        'avatar_path': profile.avatar_path,
        'avatar_url': avatar_url,
    })



@api_view(['POST'])
@permission_classes([IsAuthenticated])
def avatar_upload_url(request):
    extension = (request.data.get('extension') or '').lower()
    allowed_extensions = {'jpg', 'jpeg', 'png', 'webp'}

    if extension not in allowed_extensions:
        return Response(
            {'error': 'Only JPG, PNG and WebP images are supported.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    path = f'{request.user.pk}/avatar-{uuid.uuid4().hex}.{extension}'

    try:
        token = create_upload_permission(path)
        return Response({'path': path, 'token': token})

    except Exception:
        logging.exception(
            'Avatar signed upload URL creation failed for user %s',
            request.user.pk,
        )
        return Response(
            {'error': 'Could not create a secure upload permission.'},
            status=status.HTTP_502_BAD_GATEWAY,
        )



@api_view(['POST'])
@permission_classes([IsAuthenticated])
def avatar_upload_complete(request):
    path = (request.data.get('path') or '').strip()
    expected_prefix = f'{request.user.pk}/'
    valid_path = re.fullmatch(
        rf'{request.user.pk}/avatar-[0-9a-f]{{32}}\.(?:jpg|jpeg|png|webp)',
        path,
    )
    if not valid_path or not path.startswith(expected_prefix):
        return Response(
            {'error': 'Invalid avatar object path.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        metadata = avatar_exists(path)
        object_metadata = metadata.get('metadata') or {}
        size = object_metadata.get('size') or metadata.get('size')
        content_type = (
            object_metadata.get('mimetype')
            or object_metadata.get('contentType')
            or metadata.get('mimetype')
        )
        if size is not None and int(size) > 5 * 1024 * 1024:
            delete_avatar(path)
            return Response(
                {'error': 'Avatar must be smaller than 5 MB.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        allowed_types = {'image/jpeg', 'image/png', 'image/webp'}
        if content_type and content_type not in allowed_types:
            delete_avatar(path)
            return Response(
                {'error': 'Uploaded file is not an allowed image type.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
    except Exception:
        return Response(
            {'error': 'Uploaded avatar could not be verified in private storage.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    previous_path = profile.avatar_path
    profile.avatar_path = path
    profile.save(update_fields=['avatar_path', 'updated_at'])

    if previous_path and previous_path != path:
        try:
            delete_avatar(previous_path)
        except Exception:
            # Profile update remains successful; stale objects can be cleaned up later.
            pass

    return Response({'message': 'Profile picture updated.', 'avatar_path': path})


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def avatar_delete(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    previous_path = profile.avatar_path
    profile.avatar_path = ''
    profile.save(update_fields=['avatar_path', 'updated_at'])

    if previous_path:
        try:
            delete_avatar(previous_path)
        except Exception:
            pass

    return Response({'message': 'Profile picture removed.'})
