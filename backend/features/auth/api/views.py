
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
from core.models import OwnerApplication

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
