from decimal import Decimal

from django.db import models
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import Booking, BookingStatus, Coupon, Facility, PaymentStatus, SportType, TimeSlot
from core.serializers import CouponSerializer, FacilitySerializer
from global_utils.view_helpers import (
    COUPON_ARCHIVE_RETENTION_DAYS,
    FACILITY_ARCHIVE_RETENTION_DAYS,
    _coupon_archive_cutoff,
    _coupon_is_within_owner_retention,
    _facility_archive_cutoff,
    _facility_is_within_owner_retention,
    _is_owner_user,
    _uuid_from_user,
)
from global_utils.permissions import IsVenueOwner

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def active_coupons_endpoint(request):
    now = timezone.now()
    qs = Coupon.objects.filter(
        is_active=True,
        archived_at__isnull=True,
        starts_at__lte=now,
        ends_at__gte=now,
    ).order_by('-discount_percent', 'code')
    return Response(CouponSerializer(qs, many=True).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated, IsVenueOwner])
def owner_analytics_endpoint(request):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)
    owner_uuid = _uuid_from_user(request.user)
    facility_filter = models.Q(facility__owner_user_id=owner_uuid)
    if request.user.is_superuser:
        facility_filter = models.Q()
    bookings = Booking.objects.filter(facility_filter).select_related('facility')
    revenue = bookings.filter(payment_status=PaymentStatus.MOCK_PAID).aggregate(total=models.Sum('final_price')).get('total') or Decimal('0.00')
    refunds = bookings.aggregate(total=models.Sum('refund_amount')).get('total') or Decimal('0.00')
    cancelled = bookings.filter(status=BookingStatus.CANCELLED).count()
    return Response({
        'total_bookings': bookings.count(),
        'confirmed_bookings': bookings.filter(status=BookingStatus.CONFIRMED).count(),
        'pending_bookings': bookings.filter(status=BookingStatus.PENDING).count(),
        'cancelled_bookings': cancelled,
        'revenue': str(revenue),
        'refunds': str(refunds),
        'net_revenue': str((revenue - refunds).quantize(Decimal('0.01'))),
        'cancellation_rate': round((cancelled / bookings.count()) * 100, 2) if bookings.exists() else 0,
        'by_venue': [
            {
                'facility_name': row['facility__name'],
                'bookings': row['count'],
                'revenue': str(row['revenue'] or Decimal('0.00')),
                'cancellations': row['cancellations'],
            }
            for row in bookings.values('facility__name').annotate(
                count=models.Count('id'),
                revenue=models.Sum('final_price', filter=models.Q(payment_status=PaymentStatus.MOCK_PAID)),
                cancellations=models.Count('id', filter=models.Q(status=BookingStatus.CANCELLED)),
            ).order_by('-revenue')
        ],
    })


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated, IsVenueOwner])
def owner_facilities_endpoint(request):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        now = timezone.now()
        owner_uuid = _uuid_from_user(request.user)
        archived_only_raw = (request.query_params.get('archived_only') or '').strip().lower()
        query = (request.query_params.get('q') or '').strip()
        archived_from_raw = (request.query_params.get('archived_from') or '').strip()
        archived_to_raw = (request.query_params.get('archived_to') or '').strip()
        archive_cutoff = _facility_archive_cutoff(now)
        owner_scope = Facility.objects.all()
        if not request.user.is_superuser:
            owner_scope = owner_scope.filter(models.Q(owner_user_id=owner_uuid) | models.Q(owner_user_id__isnull=True))

        # Purge archived facilities older than retention window when they have no bookings.
        stale_ids = list(
            owner_scope.filter(archived_at__lt=archive_cutoff)
            .annotate(booking_count=models.Count('bookings'))
            .filter(booking_count=0)
            .values_list('id', flat=True)
        )
        if stale_ids:
            TimeSlot.objects.filter(facility_id__in=stale_ids).delete()
            Facility.objects.filter(id__in=stale_ids).delete()

        qs = owner_scope.filter(
            models.Q(archived_at__isnull=True) | models.Q(archived_at__gte=archive_cutoff)
        ).order_by('sport_type', 'name')

        archived_only = archived_only_raw in ['true', '1', 'yes']
        if archived_only:
            qs = qs.filter(archived_at__isnull=False)

        if query:
            qs = qs.filter(models.Q(name__icontains=query) | models.Q(location_name__icontains=query) | models.Q(sport_type__icontains=query))

        if archived_from_raw:
            archived_from = parse_datetime(archived_from_raw)
            if archived_from is not None:
                if timezone.is_naive(archived_from):
                    archived_from = timezone.make_aware(archived_from)
                qs = qs.filter(archived_at__gte=archived_from)

        if archived_to_raw:
            archived_to = parse_datetime(archived_to_raw)
            if archived_to is not None:
                if timezone.is_naive(archived_to):
                    archived_to = timezone.make_aware(archived_to)
                qs = qs.filter(archived_at__lte=archived_to)

        return Response(FacilitySerializer(qs, many=True).data)

    name = (request.data.get('name') or '').strip()
    sport_type = (request.data.get('sport_type') or '').strip().lower()
    location_name = (request.data.get('location_name') or '').strip()
    description = (request.data.get('description') or '').strip()
    image_url = (request.data.get('image_url') or '').strip()
    is_indoor_raw = request.data.get('is_indoor', False)
    if isinstance(is_indoor_raw, bool):
        is_indoor = is_indoor_raw
    elif isinstance(is_indoor_raw, str):
        is_indoor = is_indoor_raw.strip().lower() in ['true', '1', 'yes']
    else:
        is_indoor = bool(is_indoor_raw)

    base_price_raw = request.data.get('base_price_per_hour')
    latitude_raw = request.data.get('latitude', 11.5564)
    longitude_raw = request.data.get('longitude', 104.9282)

    if not name:
        return Response({'error': 'name is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not location_name:
        return Response({'error': 'location_name is required'}, status=status.HTTP_400_BAD_REQUEST)
    if sport_type not in SportType.values:
        return Response({'error': f'sport_type must be one of: {", ".join(SportType.values)}'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        base_price_per_hour = Decimal(str(base_price_raw)).quantize(Decimal('0.01'))
    except Exception:
        return Response({'error': 'base_price_per_hour must be numeric'}, status=status.HTTP_400_BAD_REQUEST)
    if base_price_per_hour <= Decimal('0.00'):
        return Response({'error': 'base_price_per_hour must be greater than zero'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        latitude = float(latitude_raw)
        longitude = float(longitude_raw)
    except Exception:
        return Response({'error': 'latitude and longitude must be numeric'}, status=status.HTTP_400_BAD_REQUEST)

    facility = Facility.objects.create(
        name=name,
        sport_type=sport_type,
        is_indoor=is_indoor,
        description=description,
        location_name=location_name,
        latitude=latitude,
        longitude=longitude,
        base_price_per_hour=base_price_per_hour,
        image_url=image_url,
        owner_user_id=_uuid_from_user(request.user),
        is_active=True,
        archived_at=None,
    )
    return Response({'type': 'facility_created', 'facility': FacilitySerializer(facility).data}, status=status.HTTP_201_CREATED)


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsAuthenticated, IsVenueOwner])
def owner_facility_detail_endpoint(request, facility_id):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    try:
        facility = Facility.objects.get(id=facility_id)
    except Facility.DoesNotExist:
        return Response({'error': 'Facility not found.'}, status=status.HTTP_404_NOT_FOUND)

    owner_uuid = _uuid_from_user(request.user)
    if facility.owner_user_id and (facility.owner_user_id != owner_uuid) and (not request.user.is_superuser):
        return Response({'error': 'You can only edit your own venues.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'DELETE':
        facility.is_active = False
        facility.archived_at = timezone.now()
        facility.owner_user_id = owner_uuid
        facility.save(update_fields=['is_active', 'archived_at', 'owner_user_id', 'updated_at'])
        return Response(
            {
                'type': 'facility_archived',
                'facility_id': facility_id,
                'facility': FacilitySerializer(facility).data,
                'retention_days': FACILITY_ARCHIVE_RETENTION_DAYS,
            }
        )

    if not _facility_is_within_owner_retention(facility):
        return Response({'error': 'Facility is outside retention window.'}, status=status.HTTP_410_GONE)

    update_fields = ['updated_at']

    if 'name' in request.data:
        name = (request.data.get('name') or '').strip()
        if not name:
            return Response({'error': 'name cannot be empty'}, status=status.HTTP_400_BAD_REQUEST)
        facility.name = name
        update_fields.append('name')

    if 'location_name' in request.data:
        location_name = (request.data.get('location_name') or '').strip()
        if not location_name:
            return Response({'error': 'location_name cannot be empty'}, status=status.HTTP_400_BAD_REQUEST)
        facility.location_name = location_name
        update_fields.append('location_name')

    if 'description' in request.data:
        facility.description = (request.data.get('description') or '').strip()
        update_fields.append('description')

    if 'image_url' in request.data:
        facility.image_url = (request.data.get('image_url') or '').strip()
        update_fields.append('image_url')

    if 'sport_type' in request.data:
        sport_type = (request.data.get('sport_type') or '').strip().lower()
        if sport_type not in SportType.values:
            return Response({'error': f'sport_type must be one of: {", ".join(SportType.values)}'}, status=status.HTTP_400_BAD_REQUEST)
        facility.sport_type = sport_type
        update_fields.append('sport_type')

    if 'is_indoor' in request.data:
        is_indoor = request.data.get('is_indoor')
        if not isinstance(is_indoor, bool):
            return Response({'error': 'is_indoor must be boolean'}, status=status.HTTP_400_BAD_REQUEST)
        facility.is_indoor = is_indoor
        update_fields.append('is_indoor')

    if 'is_active' in request.data:
        is_active = request.data.get('is_active')
        if not isinstance(is_active, bool):
            return Response({'error': 'is_active must be boolean'}, status=status.HTTP_400_BAD_REQUEST)
        facility.is_active = is_active
        update_fields.append('is_active')
        if is_active and facility.archived_at is not None:
            facility.archived_at = None
            update_fields.append('archived_at')

    if 'base_price_per_hour' in request.data:
        try:
            base_price = Decimal(str(request.data.get('base_price_per_hour'))).quantize(Decimal('0.01'))
        except Exception:
            return Response({'error': 'base_price_per_hour must be numeric'}, status=status.HTTP_400_BAD_REQUEST)
        if base_price <= Decimal('0.00'):
            return Response({'error': 'base_price_per_hour must be greater than zero'}, status=status.HTTP_400_BAD_REQUEST)
        facility.base_price_per_hour = base_price
        update_fields.append('base_price_per_hour')

    if 'latitude' in request.data:
        try:
            facility.latitude = float(request.data.get('latitude'))
        except Exception:
            return Response({'error': 'latitude must be numeric'}, status=status.HTTP_400_BAD_REQUEST)
        update_fields.append('latitude')

    if 'longitude' in request.data:
        try:
            facility.longitude = float(request.data.get('longitude'))
        except Exception:
            return Response({'error': 'longitude must be numeric'}, status=status.HTTP_400_BAD_REQUEST)
        update_fields.append('longitude')

    if len(update_fields) == 1:
        return Response({'error': 'No valid fields to update.'}, status=status.HTTP_400_BAD_REQUEST)

    facility.owner_user_id = owner_uuid
    update_fields.append('owner_user_id')
    facility.save(update_fields=update_fields)
    return Response({'type': 'facility_updated', 'facility': FacilitySerializer(facility).data})


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated, IsVenueOwner])
def owner_coupons_endpoint(request):
    if not (request.user.is_staff or request.user.is_superuser):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        now = timezone.now()
        archive_cutoff = _coupon_archive_cutoff(now)
        owner_filter = models.Q(owner_user_id=_uuid_from_user(request.user))
        if request.user.is_superuser:
            owner_filter = models.Q()
        qs = Coupon.objects.filter(owner_filter).filter(
            models.Q(archived_at__isnull=True) | models.Q(archived_at__gte=archive_cutoff)
        ).order_by('-created_at')
        return Response(CouponSerializer(qs, many=True).data)

    code = (request.data.get('code') or '').strip().upper()
    title = (request.data.get('title') or '').strip()
    description = (request.data.get('description') or '').strip()
    starts_at_raw = request.data.get('starts_at')
    ends_at_raw = request.data.get('ends_at')
    discount_percent_raw = request.data.get('discount_percent')

    if not code:
        return Response({'error': 'code is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        discount_percent = Decimal(str(discount_percent_raw))
    except Exception:
        return Response({'error': 'discount_percent must be numeric'}, status=status.HTTP_400_BAD_REQUEST)

    starts_at = parse_datetime(starts_at_raw) if starts_at_raw else None
    ends_at = parse_datetime(ends_at_raw) if ends_at_raw else None
    if starts_at is None or ends_at is None:
        return Response({'error': 'starts_at and ends_at are required in ISO format'}, status=status.HTTP_400_BAD_REQUEST)

    if timezone.is_naive(starts_at):
        starts_at = timezone.make_aware(starts_at)
    if timezone.is_naive(ends_at):
        ends_at = timezone.make_aware(ends_at)

    if ends_at <= starts_at:
        return Response({'error': 'ends_at must be after starts_at'}, status=status.HTTP_400_BAD_REQUEST)

    if discount_percent <= Decimal('0') or discount_percent > Decimal('100'):
        return Response({'error': 'discount_percent must be between 0 and 100'}, status=status.HTTP_400_BAD_REQUEST)

    owner_uuid = _uuid_from_user(request.user)
    coupon, created = Coupon.objects.update_or_create(
        code=code,
        defaults={
            'title': title,
            'description': description,
            'discount_percent': discount_percent,
            'starts_at': starts_at,
            'ends_at': ends_at,
            'is_active': True,
            'archived_at': None,
            'owner_user_id': owner_uuid,
        },
    )

    return Response(
        {
            'type': 'coupon_created' if created else 'coupon_updated',
            'coupon': CouponSerializer(coupon).data,
        },
        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsAuthenticated, IsVenueOwner])
def owner_coupon_detail_endpoint(request, coupon_id):
    if not (request.user.is_staff or request.user.is_superuser):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    try:
        coupon = Coupon.objects.get(id=coupon_id)
    except Coupon.DoesNotExist:
        return Response({'error': 'Coupon not found.'}, status=status.HTTP_404_NOT_FOUND)

    if (
        not request.user.is_superuser
        and coupon.owner_user_id != _uuid_from_user(request.user)
    ):
        return Response({'error': 'You can only manage your own coupons.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'PATCH':
        if not _coupon_is_within_owner_retention(coupon):
            return Response({'error': 'Coupon is outside retention window.'}, status=status.HTTP_410_GONE)

        is_active = request.data.get('is_active')
        if not isinstance(is_active, bool):
            return Response({'error': 'is_active must be boolean'}, status=status.HTTP_400_BAD_REQUEST)

        now = timezone.now()
        coupon.is_active = is_active
        update_fields = ['is_active', 'updated_at']
        if is_active:
            if coupon.starts_at > now:
                coupon.starts_at = now
                update_fields.append('starts_at')
            if coupon.archived_at is not None:
                coupon.archived_at = None
                update_fields.append('archived_at')

        coupon.save(update_fields=update_fields)
        return Response({'type': 'coupon_updated', 'coupon': CouponSerializer(coupon).data})

    coupon.is_active = False
    coupon.archived_at = timezone.now()
    coupon.save(update_fields=['is_active', 'archived_at', 'updated_at'])
    return Response(
        {
            'type': 'coupon_archived',
            'coupon_id': coupon_id,
            'coupon': CouponSerializer(coupon).data,
            'retention_days': COUPON_ARCHIVE_RETENTION_DAYS,
        }
    )
