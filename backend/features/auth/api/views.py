
import logging

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.mail import send_mail
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

logger = logging.getLogger(__name__)


def _notify_admin_of_owner_application(application):
    """Email the configured administrator; submission succeeds even if SMTP is down."""
    subject = f'New venue owner application: {application.venue_name}'
    message = (
        'A new venue owner application has been submitted.\n\n'
        f'Venue: {application.venue_name}\n'
        f'Applicant email: {application.user.email}\n'
        f'Contact phone: {application.contact_phone or "Not provided"}\n'
        f'Status: {application.status}\n\n'
        'Review it in Django Admin under Core → Owner applications.\n'
        'Admin path: /admin/core/ownerapplication/'
    )
    try:
        sent = send_mail(
            subject=subject,
            message=message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[settings.OWNER_APPLICATION_ADMIN_EMAIL],
            fail_silently=False,
        )
        if sent != 1:
            logger.error('Owner application email was not sent for application %s.', application.pk)
            return False
        return True
    except Exception:
        logger.exception('Could not email administrator about owner application %s.', application.pk)
        return False

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
    application = OwnerApplication.objects.create(
        user=user,
        venue_name=venue_name,
        contact_phone=phone,
        status=OwnerApplication.Status.PENDING,
    )
    notification_sent = _notify_admin_of_owner_application(application)
    token, _ = Token.objects.get_or_create(user=user)
    return Response({
        **_auth_payload(user, token),
        'message': 'Your venue owner application has been submitted and is awaiting administrator review.',
        'notification_sent': notification_sent,
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

    # Owner access is granted only after an administrator approves the application.
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
