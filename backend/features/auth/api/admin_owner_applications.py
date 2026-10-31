from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import OwnerApplication


def _require_admin(request):
    return bool(request.user and request.user.is_authenticated and
                request.user.is_superuser)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def admin_owner_applications(request):
    """List owner applications for the in-app administrator review screen."""
    if not _require_admin(request):
        return Response({'error': 'Administrator access required.'},
                        status=status.HTTP_403_FORBIDDEN)

    queryset = OwnerApplication.objects.select_related('user').order_by('-created_at')
    requested_status = (request.query_params.get('status') or '').strip().lower()
    valid_statuses = {choice[0] for choice in OwnerApplication.Status.choices}
    if requested_status:
        if requested_status not in valid_statuses:
            return Response({'error': 'Invalid status filter.'},
                            status=status.HTTP_400_BAD_REQUEST)
        queryset = queryset.filter(status=requested_status)

    return Response([
        {
            'id': item.pk,
            'venue_name': item.venue_name,
            'applicant_email': item.user.email,
            'contact_phone': item.contact_phone,
            'status': item.status,
            'created_at': item.created_at.isoformat(),
            'reviewed_at': item.reviewed_at.isoformat() if item.reviewed_at else None,
        }
        for item in queryset
    ])


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def review_owner_application(request, application_id):
    """Approve or reject a request; only superusers may call this."""
    if not _require_admin(request):
        return Response({'error': 'Administrator access required.'},
                        status=status.HTTP_403_FORBIDDEN)

    decision = (request.data.get('decision') or '').strip().lower()
    if decision not in ('approve', 'reject'):
        return Response({'error': 'decision must be approve or reject.'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        application = OwnerApplication.objects.select_related('user').get(pk=application_id)
    except OwnerApplication.DoesNotExist:
        return Response({'error': 'Application not found.'},
                        status=status.HTTP_404_NOT_FOUND)

    if application.status != OwnerApplication.Status.PENDING:
        return Response({'error': 'Only pending applications can be reviewed.'},
                        status=status.HTTP_409_CONFLICT)

    application.status = (
        OwnerApplication.Status.APPROVED
        if decision == 'approve'
        else OwnerApplication.Status.REJECTED
    )
    application.reviewed_at = timezone.now()
    application.save(update_fields=['status', 'reviewed_at'])

    if decision == 'approve':
        application.user.is_staff = True
        application.user.save(update_fields=['is_staff'])

    return Response({
        'id': application.pk,
        'status': application.status,
        'message': 'Application ' + ('approved.' if decision == 'approve' else 'rejected.'),
    })
