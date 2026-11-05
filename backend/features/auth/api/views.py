
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

def _ensure_owner_access(user):
    application = OwnerApplication.objects.filter(user_id=user.id).first()
    if application is None:
        return
    fields = []
    if application.status != OwnerApplication.Status.APPROVED:
        application.status = OwnerApplication.Status.APPROVED
        application.reviewed_at = timezone.now()
        fields.extend(['status', 'reviewed_at'])
    if fields:
        application.save(update_fields=fields)
    if not user.is_staff:
        user.is_staff = True
        user.save(update_fields=['is_staff'])

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


@api_view(['POST'])
@permission_classes([AllowAny])
def owner_signup(request):
    email = (request.data.get('email') or '').strip().lower()
    password = (request.data.get('password') or '').strip()
    venue_name = (request.data.get('venue_name') or '').strip()
    phone = (request.data.get('contact_phone') or '').strip()
    if not email or not password or not venue_name:
        return Response({'error': 'email, password, and venue_name are required'}, status=status.HTTP_400_BAD_REQUEST)
    if len(password) < 8:
        return Response({'error': 'password must be at least 8 characters'}, status=status.HTTP_400_BAD_REQUEST)
    if User.objects.filter(username=email).exists():
        return Response({'error': 'email already registered'}, status=status.HTTP_409_CONFLICT)
    user = User.objects.create_user(username=email, email=email, password=password)
    user.is_staff = True
    user.save(update_fields=['is_staff'])
    OwnerApplication.objects.create(
        user=user,
        venue_name=venue_name,
        contact_phone=phone,
        status=OwnerApplication.Status.APPROVED,
        reviewed_at=timezone.now(),
    )
    token, _ = Token.objects.get_or_create(user=user)
    return Response({
        **_auth_payload(user, token),
        'message': 'Admin venue account created. You can now use the owner dashboard.',
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

    _ensure_owner_access(user)
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

    return Response({
        'display_name': profile.display_name,
        'preferred_city': profile.preferred_city,
        'favorite_sport': profile.favorite_sport,
        'push_notifications': profile.push_notifications,
        'special_offers': profile.special_offers,
    })
