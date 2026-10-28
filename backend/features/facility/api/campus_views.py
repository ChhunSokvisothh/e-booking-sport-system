from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from core.campus_serializers import CampusSerializer
from core.models import Campus, CampusPhoto, Facility
from global_utils.view_helpers import _is_owner_user, _uuid_from_user


def _campus_payload(campus):
    return CampusSerializer(campus).data


@api_view(['GET'])
@permission_classes([AllowAny])
def campus_list_endpoint(request):
    qs = Campus.objects.filter(is_active=True, facilities__is_active=True).distinct().prefetch_related('photos', 'facilities')
    sport_type = (request.query_params.get('sport_type') or '').strip().lower()
    query = (request.query_params.get('q') or '').strip()
    if sport_type:
        qs = qs.filter(facilities__sport_type=sport_type)
    if query:
        qs = qs.filter(name__icontains=query) | qs.filter(address__icontains=query)
    return Response([_campus_payload(campus) for campus in qs.order_by('name')])


@api_view(['GET'])
@permission_classes([AllowAny])
def campus_detail_endpoint(request, campus_id):
    try:
        campus = Campus.objects.prefetch_related('photos', 'facilities').get(pk=campus_id, is_active=True)
    except Campus.DoesNotExist:
        return Response({'error': 'Campus not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response(_campus_payload(campus))


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def owner_campus_endpoint(request):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)
    owner_uuid = _uuid_from_user(request.user)
    campus = Campus.objects.filter(owner_user_id=owner_uuid).order_by('-created_at').first()
    if campus is None:
        return Response({'error': 'No campus profile exists for this owner yet.'}, status=status.HTTP_404_NOT_FOUND)
    if request.method == 'GET':
        return Response(_campus_payload(campus))

    scalar_fields = {
        'name': ('name', 160),
        'description': ('description', None),
        'address': ('address', 255),
        'contact_phone': ('contact_phone', 40),
        'contact_email': ('contact_email', 254),
        'cover_image_url': ('cover_image_url', None),
        'cancellation_policy': ('cancellation_policy', None),
    }
    update_fields = []
    for key, (field, max_length) in scalar_fields.items():
        if key in request.data:
            value = str(request.data.get(key) or '').strip()
            if key in ('name', 'address') and not value:
                return Response({'error': f'{key} cannot be empty.'}, status=status.HTTP_400_BAD_REQUEST)
            if max_length and len(value) > max_length:
                return Response({'error': f'{key} exceeds {max_length} characters.'}, status=status.HTTP_400_BAD_REQUEST)
            setattr(campus, field, value)
            update_fields.append(field)

    for key in ('latitude', 'longitude'):
        if key in request.data:
            try:
                value = float(request.data[key])
            except (TypeError, ValueError):
                return Response({'error': f'{key} must be numeric.'}, status=status.HTTP_400_BAD_REQUEST)
            if (key == 'latitude' and not -90 <= value <= 90) or (key == 'longitude' and not -180 <= value <= 180):
                return Response({'error': f'{key} is outside valid coordinates.'}, status=status.HTTP_400_BAD_REQUEST)
            setattr(campus, key, value)
            update_fields.append(key)

    if 'amenities' in request.data:
        amenities = request.data['amenities']
        if not isinstance(amenities, list) or not all(isinstance(item, str) for item in amenities):
            return Response({'error': 'amenities must be a list of strings.'}, status=status.HTTP_400_BAD_REQUEST)
        campus.amenities = list(dict.fromkeys(item.strip() for item in amenities if item.strip()))
        update_fields.append('amenities')

    if 'opening_hours' in request.data:
        hours = request.data['opening_hours']
        if not isinstance(hours, dict):
            return Response({'error': 'opening_hours must be an object keyed by day.'}, status=status.HTTP_400_BAD_REQUEST)
        campus.opening_hours = hours
        update_fields.append('opening_hours')

    if 'gallery_image_urls' in request.data:
        urls = request.data['gallery_image_urls']
        if not isinstance(urls, list) or len(urls) > 20 or not all(isinstance(url, str) and url.startswith(('https://', 'http://')) for url in urls):
            return Response({'error': 'gallery_image_urls must be a list of up to 20 HTTP(S) image URLs.'}, status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            CampusPhoto.objects.filter(campus=campus).delete()
            CampusPhoto.objects.bulk_create([
                CampusPhoto(campus=campus, image_url=url.strip(), sort_order=index)
                for index, url in enumerate(dict.fromkeys(url.strip() for url in urls if url.strip()))
            ])

    if update_fields:
        campus.save(update_fields=update_fields + ['updated_at'])
    campus.refresh_from_db()
    return Response(_campus_payload(campus))
