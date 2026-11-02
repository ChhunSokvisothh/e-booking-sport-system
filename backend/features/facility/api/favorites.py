from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status

from core.models import Facility, FavoriteFacility


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def favorite_facilities_endpoint(request):
    """List the current user's saved venue IDs or save a venue."""
    if request.method == 'GET':
        ids = list(
            FavoriteFacility.objects.filter(user=request.user)
            .values_list('facility_id', flat=True)
        )
        return Response({'facility_ids': ids})

    facility_id = request.data.get('facility_id')
    try:
        facility_id = int(facility_id)
    except (TypeError, ValueError):
        return Response(
            {'error': 'facility_id must be an integer.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    facility = Facility.objects.filter(id=facility_id, is_active=True).first()
    if facility is None:
        return Response(
            {'error': 'Venue not found.'},
            status=status.HTTP_404_NOT_FOUND,
        )

    favorite, created = FavoriteFacility.objects.get_or_create(
        user=request.user,
        facility=facility,
    )
    return Response(
        {'facility_id': favorite.facility_id, 'saved': True},
        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def remove_favorite_facility_endpoint(request, facility_id):
    FavoriteFacility.objects.filter(
        user=request.user,
        facility_id=facility_id,
    ).delete()
    return Response({'facility_id': facility_id, 'saved': False}, status=status.HTTP_200_OK)
