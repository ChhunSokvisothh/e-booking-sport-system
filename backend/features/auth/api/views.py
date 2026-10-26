
from django.contrib.auth import authenticate
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
    return Response(
        {
            'token': token.key,
            'user_id': user.id,
            'user_uuid': str(_uuid_from_user(user)),
            'email': user.email,
            'role': _role_for_user(user),
        },
        status=status.HTTP_201_CREATED,
    )


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
    return Response(
        {
            'token': token.key,
            'user_id': user.id,
            'user_uuid': str(_uuid_from_user(user)),
            'email': user.email,
            'role': _role_for_user(user),
        }
    )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def auth_logout(request):
    Token.objects.filter(user=request.user).delete()
    return Response({'ok': True})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def auth_me(request):
    return Response(
        {
            'user_id': request.user.id,
            'user_uuid': str(_uuid_from_user(request.user)),
            'email': request.user.email,
            'role': _role_for_user(request.user),
        }
    )

