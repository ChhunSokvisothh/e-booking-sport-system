import json
import re
import threading
import uuid
from datetime import datetime, timedelta, timezone as dt_timezone
from difflib import SequenceMatcher
from decimal import Decimal

import requests
from django.conf import settings
from django.contrib.auth import authenticate, get_user_model
from django.core.cache import cache
from django.db import models, transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status, viewsets
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from supabase import Client, create_client

from .models import Booking, BookingSource, BookingStatus, Coupon, Facility, PaymentStatus, Profile, SportType, TimeSlot
from .serializers import BookingSerializer, CouponSerializer, FacilitySerializer, TimeSlotSerializer


User = get_user_model()

BOOKING_WINDOW_DAYS = 15
ROLLING_SLOT_REFRESH_SECONDS = 60
PAYMENT_WINDOW_MINUTES = 5
COUPON_ARCHIVE_RETENTION_DAYS = 90
FACILITY_ARCHIVE_RETENTION_DAYS = 90


def _coupon_archive_cutoff(now=None):
    now = now or timezone.now()
    return now - timedelta(days=COUPON_ARCHIVE_RETENTION_DAYS)


def _coupon_is_within_owner_retention(coupon, now=None):
    if coupon.archived_at is None:
        return True
    return coupon.archived_at >= _coupon_archive_cutoff(now)


def _facility_archive_cutoff(now=None):
    now = now or timezone.now()
    return now - timedelta(days=FACILITY_ARCHIVE_RETENTION_DAYS)


def _facility_is_within_owner_retention(facility, now=None):
    if facility.archived_at is None:
        return True
    return facility.archived_at >= _facility_archive_cutoff(now)


def _role_for_user(user):
    if not user or not user.is_authenticated:
        return 'anon'
    if user.is_superuser:
        return 'superadmin'
    profile, _ = Profile.objects.get_or_create(user=user)
    return profile.role


def _is_owner_user(user):
    return _role_for_user(user) in ('owner', 'admin', 'superadmin')


def _is_admin_user(user):
    return _role_for_user(user) in ('admin', 'superadmin')


class FacilityPagination(PageNumberPagination):
    page_size = 12
    page_size_query_param = 'page_size'
    max_page_size = 40


class SlotPagination(PageNumberPagination):
    page_size = 24
    page_size_query_param = 'page_size'
    max_page_size = 80


def _request_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    if forwarded:
        return forwarded.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def _rate_limit_check(request, action, identifier, limit=5, window_seconds=60):
    ip = _request_ip(request)
    key = f'rl:{action}:{ip}:{identifier.lower().strip()}'
    current = cache.get(key, 0)
    if current >= limit:
        return False
    cache.set(key, current + 1, timeout=window_seconds)
    return True


def _uuid_from_user(user):
    return uuid.uuid5(uuid.NAMESPACE_URL, f'e-booking-user:{user.id}')


class FacilityViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = FacilitySerializer
    queryset = Facility.objects.filter(is_active=True)
    pagination_class = FacilityPagination

    def get_queryset(self):
        qs = super().get_queryset()
        sport_type = self.request.query_params.get('sport_type')
        is_indoor = self.request.query_params.get('is_indoor')
        query = (self.request.query_params.get('q') or '').strip()
        featured = (self.request.query_params.get('featured') or '').lower() in ['true', '1', 'yes']

        if sport_type:
            qs = qs.filter(sport_type=sport_type)
        if is_indoor is not None:
            if is_indoor.lower() in ['true', '1']:
                qs = qs.filter(is_indoor=True)
            elif is_indoor.lower() in ['false', '0']:
                qs = qs.filter(is_indoor=False)

        if query:
            qs = qs.filter(models.Q(name__icontains=query) | models.Q(location_name__icontains=query))
            qs = qs.annotate(
                relevance=models.Case(
                    models.When(name__istartswith=query, then=models.Value(0)),
                    models.When(location_name__istartswith=query, then=models.Value(1)),
                    models.When(name__icontains=query, then=models.Value(2)),
                    models.When(location_name__icontains=query, then=models.Value(3)),
                    default=models.Value(4),
                    output_field=models.IntegerField(),
                )
            )

        if featured:
            if query:
                return qs.order_by('relevance', '-rating', 'name')
            return qs.order_by('-rating', 'name')

        if query:
            return qs.order_by('relevance', '-rating', 'name')

        return qs.order_by('sport_type', 'name')


class TimeSlotViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = TimeSlotSerializer
    queryset = TimeSlot.objects.select_related('facility').filter(facility__is_active=True, is_open=True)
    pagination_class = SlotPagination

    def get_queryset(self):
        qs = super().get_queryset()

        facility_id = self.request.query_params.get('facility_id')
        sport_type = self.request.query_params.get('sport_type')
        date_str = self.request.query_params.get('date')
        only_available = self.request.query_params.get('only_available', 'true').lower() in ['true', '1']

        if facility_id:
            qs = qs.filter(facility_id=facility_id)
        if sport_type:
            qs = qs.filter(facility__sport_type=sport_type)
        if date_str:
            try:
                d = datetime.strptime(date_str, '%Y-%m-%d').date()
                start_of_day = timezone.make_aware(datetime.combine(d, datetime.min.time()))
                end_of_day = start_of_day + timedelta(days=1)
                qs = qs.filter(start_at__gte=start_of_day, start_at__lt=end_of_day)
            except ValueError:
                pass

        if only_available:
            qs = qs.filter(current_bookings__lt=models.F('max_bookings'))

        return qs.order_by('start_at')


@api_view(['GET'])
@permission_classes([AllowAny])
def live_slots_endpoint(request):
    _release_expired_pending_bookings()
    _ensure_rolling_slot_window_cached()
    sport_type = (request.query_params.get('sport_type') or '').strip().lower()
    date_str = (request.query_params.get('date') or '').strip()
    is_indoor_raw = request.query_params.get('is_indoor')
    requested_date, day_start, day_end = _date_bounds_for_query(date_str)
    now = timezone.now()
    local_today = timezone.localdate()

    facilities_qs = Facility.objects.filter(is_active=True)
    if sport_type:
        facilities_qs = facilities_qs.filter(sport_type=sport_type)

    if is_indoor_raw is not None:
        val = is_indoor_raw.lower()
        if val in ['true', '1']:
            facilities_qs = facilities_qs.filter(is_indoor=True)
        elif val in ['false', '0']:
            facilities_qs = facilities_qs.filter(is_indoor=False)

    facilities = list(facilities_qs)
    if not facilities:
        return Response([])

    facility_map = {f.id: f for f in facilities}
    facility_map_by_str = {str(f.id): f for f in facilities}
    facility_ids = list(facility_map.keys())
    booked_slot_ids = _booked_slot_ids_for_user(request)

    local_qs = TimeSlot.objects.select_related('facility').filter(facility__in=facilities)
    if day_start is not None and day_end is not None:
        local_qs = local_qs.filter(start_at__gte=day_start, start_at__lt=day_end)
    local_slots = list(local_qs.order_by('start_at'))
    local_slot_map = {str(slot.id): slot for slot in local_slots}

    # Source of truth for availability must be Django DB to keep account views consistent.
    rows = []

    output = []
    seen_slot_ids = set()
    for row in rows:
        slot_id = str(row.get('id'))
        local_slot = local_slot_map.get(slot_id)

        if local_slot is not None:
            facility = local_slot.facility
            start_at = local_slot.start_at
            end_at = local_slot.end_at
            current = int(local_slot.current_bookings)
            max_bookings = int(local_slot.max_bookings)
            is_open = bool(local_slot.is_open)
            hold_until = local_slot.reservation_hold_until
            slot_version = int(local_slot.slot_version)
        else:
            facility_id = row.get('facility_id')
            facility = facility_map.get(facility_id) or facility_map_by_str.get(str(facility_id))
            if facility is None:
                continue

            start_at = parse_datetime(row.get('start_at') or '')
            end_at = parse_datetime(row.get('end_at') or '')
            if not start_at or not end_at:
                continue

            if timezone.is_naive(start_at):
                start_at = timezone.make_aware(start_at)
            if timezone.is_naive(end_at):
                end_at = timezone.make_aware(end_at)

            current = int(row.get('current_bookings') or 0)
            max_bookings = int(row.get('max_bookings') or 0)
            is_open = bool(row.get('is_open', True))
            hold_until_raw = row.get('reservation_hold_until')
            hold_until = parse_datetime(hold_until_raw) if hold_until_raw else None
            if hold_until is not None and timezone.is_naive(hold_until):
                hold_until = timezone.make_aware(hold_until)
            slot_version = int(row.get('slot_version') or 1)

        if requested_date is not None and start_at.date() != requested_date:
            continue
        if start_at < now and (requested_date is None or requested_date == local_today):
            continue

        has_active_hold = bool(hold_until and hold_until > timezone.now())
        is_available = is_open and current == 0 and not has_active_hold

        output.append(
            {
                'slot_id': slot_id,
                'facility_id': str(facility.id),
                'facility_name': facility.name,
                'sport_type': facility.sport_type,
                'start_at': start_at,
                'end_at': end_at,
                'current_bookings': current,
                'max_bookings': max_bookings,
                'is_open': is_open,
                'is_available': is_available,
                'slot_version': slot_version,
                'reservation_hold_until': hold_until,
                'booked_by_me': slot_id in booked_slot_ids,
                'base_price_per_hour': float(facility.base_price_per_hour),
                'is_indoor': facility.is_indoor,
                'location_name': facility.location_name,
            }
        )
        seen_slot_ids.add(slot_id)

    for slot in local_slots:
        slot_id = str(slot.id)
        if slot_id in seen_slot_ids:
            continue

        has_active_hold = bool(slot.reservation_hold_until and slot.reservation_hold_until > timezone.now())
        is_available = slot.is_open and slot.current_bookings == 0 and not has_active_hold
        if slot.start_at < now and (requested_date is None or requested_date == local_today):
            continue
        output.append(
            {
                'slot_id': slot_id,
                'facility_id': str(slot.facility_id),
                'facility_name': slot.facility.name,
                'sport_type': slot.facility.sport_type,
                'start_at': slot.start_at,
                'end_at': slot.end_at,
                'current_bookings': slot.current_bookings,
                'max_bookings': slot.max_bookings,
                'is_open': slot.is_open,
                'is_available': is_available,
                'slot_version': slot.slot_version,
                'reservation_hold_until': slot.reservation_hold_until,
                'booked_by_me': slot_id in booked_slot_ids,
                'base_price_per_hour': float(slot.facility.base_price_per_hour),
                'is_indoor': slot.facility.is_indoor,
                'location_name': slot.facility.location_name,
            }
        )

    if not output:
        for slot in local_slots:
            if slot.start_at < now and (requested_date is None or requested_date == local_today):
                continue
            output.append(
                {
                    'slot_id': str(slot.id),
                    'facility_id': str(slot.facility_id),
                    'facility_name': slot.facility.name,
                    'sport_type': slot.facility.sport_type,
                    'start_at': slot.start_at,
                    'end_at': slot.end_at,
                    'current_bookings': slot.current_bookings,
                    'max_bookings': slot.max_bookings,
                    'is_open': slot.is_open,
                    'is_available': slot.has_space and not bool(slot.reservation_hold_until and slot.reservation_hold_until > timezone.now()),
                    'slot_version': slot.slot_version,
                    'reservation_hold_until': slot.reservation_hold_until,
                    'booked_by_me': str(slot.id) in booked_slot_ids,
                    'base_price_per_hour': float(slot.facility.base_price_per_hour),
                    'is_indoor': slot.facility.is_indoor,
                    'location_name': slot.facility.location_name,
                }
            )

    output.sort(key=lambda item: item['start_at'])
    return Response(output)


class BookingViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = BookingSerializer
    queryset = Booking.objects.select_related('facility', 'time_slot').all()
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        if not _is_owner_user(self.request.user):
            user_uuid = _uuid_from_user(self.request.user)
            _release_expired_pending_bookings(user_uuid=user_uuid)
            qs = qs.filter(user_id=user_uuid)
        elif not self.request.user.is_superuser:
            # Owner accounts should see bookings from facilities they own for consistent analytics.
            owner_uuid = _uuid_from_user(self.request.user)
            qs = qs.filter(models.Q(facility__owner_user_id=owner_uuid) | models.Q(facility__owner_user_id__isnull=True))

        status_filter = (self.request.query_params.get('status') or '').strip().lower()
        payment_filter = (self.request.query_params.get('payment_status') or '').strip().lower()
        upcoming_raw = (self.request.query_params.get('upcoming') or '').strip().lower()

        if status_filter:
            statuses = [item.strip() for item in status_filter.split(',') if item.strip()]
            if statuses:
                qs = qs.filter(status__in=statuses)

        if payment_filter:
            payments = [item.strip() for item in payment_filter.split(',') if item.strip()]
            if payments:
                qs = qs.filter(payment_status__in=payments)

        if upcoming_raw in ['true', '1', 'yes']:
            qs = qs.filter(start_at__gte=timezone.now()).exclude(status=BookingStatus.CANCELLED)
        elif upcoming_raw in ['false', '0', 'no']:
            qs = qs.filter(start_at__lt=timezone.now())

        return qs.order_by('-created_at')


def _slot_status(is_open, current_bookings, max_bookings):
    if not is_open:
        return 'closed'
    if max_bookings <= 0:
        return 'full'
    if current_bookings >= max_bookings:
        return 'full'

    remaining = max_bookings - current_bookings
    if remaining <= 1:
        return 'limited'
    return 'available'


def _slot_payload(
    slot_id,
    facility,
    start_at,
    end_at,
    current_bookings,
    max_bookings,
    is_open,
    slot_version=1,
    reservation_hold_until=None,
    booked_by_me=False,
):
    hold_until = reservation_hold_until
    if isinstance(hold_until, str):
        hold_until = parse_datetime(hold_until)
    if hold_until is not None and timezone.is_naive(hold_until):
        hold_until = timezone.make_aware(hold_until)

    has_active_hold = bool(hold_until and hold_until > timezone.now())
    status = _slot_status(is_open, current_bookings, max_bookings)
    if current_bookings > 0 and status in ['available', 'limited']:
        status = 'full'
    if has_active_hold and status in ['available', 'limited']:
        status = 'held'
    available_spots = max(0, max_bookings - current_bookings)

    return {
        'slot_id': str(slot_id),
        'facility_id': str(facility.id),
        'facility_name': facility.name,
        'sport_type': facility.sport_type,
        'start_at': start_at,
        'end_at': end_at,
        'current_bookings': current_bookings,
        'max_bookings': max_bookings,
        'available_spots': available_spots,
        'is_open': is_open,
        'is_available': status in ['available', 'limited'],
        'availability_status': status,
        'slot_version': slot_version,
        'reservation_hold_until': hold_until,
        'booked_by_me': bool(booked_by_me),
        'base_price_per_hour': float(facility.base_price_per_hour),
        'is_indoor': facility.is_indoor,
        'location_name': facility.location_name,
    }


def _booking_window_bounds():
    local_today = timezone.localdate()
    start = timezone.make_aware(datetime.combine(local_today, datetime.min.time()))
    end = start + timedelta(days=BOOKING_WINDOW_DAYS + 1)
    return start, end


def _ensure_rolling_slot_window():
    window_start, window_end = _booking_window_bounds()
    local_tz = timezone.get_current_timezone()

    all_facilities = list(Facility.objects.filter(is_active=True))
    template_map = {}
    for facility in all_facilities:
        historical_slots = list(TimeSlot.objects.filter(facility=facility).order_by('start_at'))
        if historical_slots:
            first_local_day = historical_slots[0].start_at.astimezone(local_tz).date()
            template_slots = [
                slot
                for slot in historical_slots
                if slot.start_at.astimezone(local_tz).date() == first_local_day
            ]
        else:
            template_slots = []

        templates = []
        for slot in template_slots:
            start_local = slot.start_at.astimezone(local_tz)
            end_local = slot.end_at.astimezone(local_tz)
            cursor = start_local
            while cursor + timedelta(hours=1) <= end_local:
                next_cursor = cursor + timedelta(hours=1)
                templates.append(
                    {
                        'start_time': cursor.timetz().replace(tzinfo=None),
                        'end_time': next_cursor.timetz().replace(tzinfo=None),
                        'duration': timedelta(hours=1),
                        'max_bookings': int(slot.max_bookings or 1),
                    }
                )
                cursor = next_cursor

        if not templates:
            # Fallback timetable when no seed data exists for a facility.
            for hour in [8, 10, 12, 14, 16, 18, 20]:
                start_time = datetime.strptime(f'{hour:02d}:00', '%H:%M').time()
                end_time = datetime.strptime(f'{hour + 2:02d}:00', '%H:%M').time()
                templates.append(
                    {
                        'start_time': start_time,
                        'end_time': end_time,
                        'duration': timedelta(hours=2),
                        'max_bookings': 3,
                    }
                )

        template_map[facility.id] = templates

    # Keep only slots within rolling window for availability; preserve historical rows with bookings.
    out_of_window = TimeSlot.objects.filter(models.Q(start_at__lt=window_start) | models.Q(start_at__gte=window_end))
    removable_ids = list(
        out_of_window.annotate(active_booking_count=models.Count('bookings'))
        .filter(active_booking_count=0)
        .values_list('id', flat=True)
    )
    if removable_ids:
        TimeSlot.objects.filter(id__in=removable_ids).delete()
        try:
            supabase = _get_supabase_client()
            supabase.table(settings.SUPABASE_TIMESLOT_TABLE).delete().in_('id', removable_ids).execute()
        except Exception:
            pass

    protected_ids = list(
        out_of_window.exclude(id__in=removable_ids).values_list('id', flat=True)
    )
    if protected_ids:
        TimeSlot.objects.filter(id__in=protected_ids).update(is_open=False, reservation_hold_until=None)

    for facility in all_facilities:
        # Normalize existing future slots to 1-hour granularity for booking UX.
        split_candidates = list(
            TimeSlot.objects.filter(facility=facility, start_at__gte=window_start, start_at__lt=window_end)
            .annotate(active_booking_count=models.Count('bookings'))
        )
        split_new_rows = []
        split_remove_ids = []
        for slot in split_candidates:
            if slot.active_booking_count > 0:
                continue

            duration = slot.end_at - slot.start_at
            if duration <= timedelta(hours=1):
                continue

            cursor = slot.start_at
            while cursor + timedelta(hours=1) <= slot.end_at:
                split_new_rows.append(
                    TimeSlot(
                        facility=facility,
                        start_at=cursor,
                        end_at=cursor + timedelta(hours=1),
                        max_bookings=slot.max_bookings,
                        current_bookings=0,
                        is_open=True,
                        reservation_hold_until=None,
                    )
                )
                cursor = cursor + timedelta(hours=1)
            split_remove_ids.append(slot.id)

        if split_new_rows:
            TimeSlot.objects.bulk_create(split_new_rows, ignore_conflicts=True)
            _sync_generated_slots_to_supabase_async(split_new_rows)
        if split_remove_ids:
            TimeSlot.objects.filter(id__in=split_remove_ids).delete()
            try:
                supabase = _get_supabase_client()
                supabase.table(settings.SUPABASE_TIMESLOT_TABLE).delete().in_('id', split_remove_ids).execute()
            except Exception:
                pass

        templates = template_map.get(facility.id) or []
        if not templates:
            continue

        existing_dates = {
            slot.start_at.astimezone(timezone.get_current_timezone()).date()
            for slot in TimeSlot.objects.filter(facility=facility, start_at__gte=window_start, start_at__lt=window_end)
        }

        created_slots = []
        for day_offset in range(BOOKING_WINDOW_DAYS + 1):
            target_date = (window_start + timedelta(days=day_offset)).date()
            if target_date in existing_dates:
                continue

            for template in templates:
                start_dt = timezone.make_aware(datetime.combine(target_date, template['start_time']))
                end_dt = timezone.make_aware(datetime.combine(target_date, template['end_time']))
                if end_dt <= start_dt:
                    end_dt = start_dt + template['duration']

                created_slots.append(
                    TimeSlot(
                        facility=facility,
                        start_at=start_dt,
                        end_at=end_dt,
                        max_bookings=template['max_bookings'],
                        current_bookings=0,
                        is_open=True,
                        reservation_hold_until=None,
                    )
                )

        if created_slots:
            TimeSlot.objects.bulk_create(created_slots)
            _sync_generated_slots_to_supabase_async(created_slots)


def _ensure_rolling_slot_window_cached():
    # Avoid repeating heavy rolling-window sync work for every request.
    cache_key = 'rolling-slot-window:last-run'
    lock_key = 'rolling-slot-window:lock'

    last_run = cache.get(cache_key)
    now_ts = timezone.now().timestamp()
    if isinstance(last_run, (int, float)) and (now_ts - float(last_run)) < ROLLING_SLOT_REFRESH_SECONDS:
        return

    if not cache.add(lock_key, '1', timeout=30):
        return

    try:
        _ensure_rolling_slot_window()
        cache.set(cache_key, now_ts, timeout=ROLLING_SLOT_REFRESH_SECONDS)
    finally:
        cache.delete(lock_key)


def _booked_slot_ids_for_user(request):
    user = getattr(request, 'user', None)
    if user is None or not user.is_authenticated:
        return set()

    user_uuid = _uuid_from_user(user)
    ids = Booking.objects.filter(
        user_id=user_uuid,
        start_at__gte=timezone.now() - timedelta(days=1),
    ).exclude(status=BookingStatus.CANCELLED).values_list('time_slot_id', flat=True)
    return {str(slot_id) for slot_id in ids}


@api_view(['GET'])
@permission_classes([AllowAny])
def slot_availability_endpoint(request):
    _release_expired_pending_bookings()
    _ensure_rolling_slot_window_cached()
    sport_type = (request.query_params.get('sport_type') or '').strip().lower()
    date_str = (request.query_params.get('date') or '').strip()
    facility_id = (request.query_params.get('facility_id') or '').strip()
    is_indoor_raw = request.query_params.get('is_indoor')
    requested_date, day_start, day_end = _date_bounds_for_query(date_str)
    now = timezone.now()
    local_today = timezone.localdate()

    facilities_qs = Facility.objects.filter(is_active=True)
    if sport_type:
        facilities_qs = facilities_qs.filter(sport_type=sport_type)
    if facility_id:
        facilities_qs = facilities_qs.filter(id=facility_id)

    if is_indoor_raw is not None:
        val = is_indoor_raw.lower()
        if val in ['true', '1']:
            facilities_qs = facilities_qs.filter(is_indoor=True)
        elif val in ['false', '0']:
            facilities_qs = facilities_qs.filter(is_indoor=False)

    facilities = list(facilities_qs)
    if not facilities:
        return Response({'date': date_str or None, 'facilities': []})

    facility_map = {f.id: f for f in facilities}
    facility_map_by_str = {str(f.id): f for f in facilities}
    facility_ids = list(facility_map.keys())
    booked_slot_ids = _booked_slot_ids_for_user(request)

    local_qs = TimeSlot.objects.select_related('facility').filter(facility__in=facilities)
    if day_start is not None and day_end is not None:
        local_qs = local_qs.filter(start_at__gte=day_start, start_at__lt=day_end)
    local_slots = list(local_qs.order_by('start_at'))
    local_slot_map = {str(slot.id): slot for slot in local_slots}

    output = []
    # Source of truth for availability must be Django DB to keep account views consistent.
    rows = []

    seen_slot_ids = set()
    for row in rows:
        slot_id = str(row.get('id'))
        local_slot = local_slot_map.get(slot_id)

        if local_slot is not None:
            facility = local_slot.facility
            start_at = local_slot.start_at
            end_at = local_slot.end_at
            current = int(local_slot.current_bookings)
            max_bookings = int(local_slot.max_bookings)
            is_open = bool(local_slot.is_open)
            slot_version = int(local_slot.slot_version)
            hold_until = local_slot.reservation_hold_until
        else:
            facility_ref = row.get('facility_id')
            facility = facility_map.get(facility_ref) or facility_map_by_str.get(str(facility_ref))
            if facility is None:
                continue

            start_at = parse_datetime(row.get('start_at') or '')
            end_at = parse_datetime(row.get('end_at') or '')
            if not start_at or not end_at:
                continue

            if timezone.is_naive(start_at):
                start_at = timezone.make_aware(start_at)
            if timezone.is_naive(end_at):
                end_at = timezone.make_aware(end_at)

            current = int(row.get('current_bookings') or 0)
            max_bookings = int(row.get('max_bookings') or 0)
            is_open = bool(row.get('is_open', True))
            slot_version = int(row.get('slot_version') or 1)
            hold_until = row.get('reservation_hold_until')

        if requested_date is not None and start_at.date() != requested_date:
            continue
        if start_at < now and (requested_date is None or requested_date == local_today):
            continue

        output.append(
            _slot_payload(
                slot_id=slot_id,
                facility=facility,
                start_at=start_at,
                end_at=end_at,
                current_bookings=current,
                max_bookings=max_bookings,
                is_open=is_open,
                slot_version=slot_version,
                reservation_hold_until=hold_until,
                booked_by_me=slot_id in booked_slot_ids,
            )
        )
        seen_slot_ids.add(slot_id)

    for slot in local_slots:
        slot_id = str(slot.id)
        if slot_id in seen_slot_ids:
            continue
        if slot.start_at < now and (requested_date is None or requested_date == local_today):
            continue

        output.append(
            _slot_payload(
                slot_id=slot_id,
                facility=slot.facility,
                start_at=slot.start_at,
                end_at=slot.end_at,
                current_bookings=slot.current_bookings,
                max_bookings=slot.max_bookings,
                is_open=slot.is_open,
                slot_version=slot.slot_version,
                reservation_hold_until=slot.reservation_hold_until,
                booked_by_me=slot_id in booked_slot_ids,
            )
        )

    if not output:
        for slot in local_slots:
            if slot.start_at < now and (requested_date is None or requested_date == local_today):
                continue
            output.append(
                _slot_payload(
                    slot_id=slot.id,
                    facility=slot.facility,
                    start_at=slot.start_at,
                    end_at=slot.end_at,
                    current_bookings=slot.current_bookings,
                    max_bookings=slot.max_bookings,
                    is_open=slot.is_open,
                    slot_version=slot.slot_version,
                    reservation_hold_until=slot.reservation_hold_until,
                    booked_by_me=str(slot.id) in booked_slot_ids,
                )
            )

    output.sort(key=lambda item: item['start_at'])

    grouped = {}
    for row in output:
        f_key = row['facility_id']
        entry = grouped.get(f_key)
        if entry is None:
            entry = {
                'facility_id': row['facility_id'],
                'facility_name': row['facility_name'],
                'sport_type': row['sport_type'],
                'is_indoor': row['is_indoor'],
                'location_name': row['location_name'],
                'base_price_per_hour': row['base_price_per_hour'],
                'total_slots': 0,
                'available_slots': 0,
                'slots': [],
            }
            grouped[f_key] = entry

        entry['total_slots'] += 1
        if row['is_available']:
            entry['available_slots'] += 1
        entry['slots'].append(
            {
                'slot_id': row['slot_id'],
                'start_at': row['start_at'],
                'end_at': row['end_at'],
                'current_bookings': row['current_bookings'],
                'max_bookings': row['max_bookings'],
                'available_spots': row['available_spots'],
                'is_open': row['is_open'],
                'is_available': row['is_available'],
                'availability_status': row['availability_status'],
                'slot_version': row['slot_version'],
                'reservation_hold_until': row['reservation_hold_until'],
            }
        )

    facilities_payload = sorted(
        grouped.values(),
        key=lambda item: (
            -(item['available_slots']),
            item['facility_name'].lower(),
        ),
    )

    return Response(
        {
            'date': date_str or None,
            'generated_at': timezone.now(),
            'facilities': facilities_payload,
        }
    )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def cancel_booking_endpoint(request, booking_id):
    user_uuid = _uuid_from_user(request.user)

    try:
        booking = Booking.objects.select_related('time_slot').get(id=booking_id, user_id=user_uuid)
    except Booking.DoesNotExist:
        return Response({'error': 'booking not found'}, status=status.HTTP_404_NOT_FOUND)

    if booking.status == BookingStatus.CANCELLED:
        return Response({'error': 'booking already cancelled'}, status=status.HTTP_409_CONFLICT)

    if booking.start_at <= timezone.now():
        return Response({'error': 'past bookings cannot be cancelled'}, status=status.HTTP_400_BAD_REQUEST)

    with transaction.atomic():
        slot = TimeSlot.objects.select_for_update().get(id=booking.time_slot_id)
        if slot.current_bookings > 0:
            slot.current_bookings -= 1
        slot.reservation_hold_until = None
        # Re-open slot only when no active booking remains.
        slot.is_open = slot.current_bookings == 0
        slot.save(
            update_fields=[
                'current_bookings',
                'reservation_hold_until',
                'is_open',
                'availability_state',
                'updated_at',
            ]
        )

        booking.status = BookingStatus.CANCELLED
        if booking.payment_status == PaymentStatus.MOCK_PENDING:
            booking.payment_status = PaymentStatus.MOCK_FAILED
        booking.save(update_fields=['status', 'payment_status', 'updated_at'])

    _sync_to_supabase_async(slot=slot, booking=booking)

    return Response(
        {
            'type': 'booking_cancelled',
            'booking_id': booking.id,
            'status': booking.status,
            'payment_status': booking.payment_status,
        }
    )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def dashboard_summary_endpoint(request):
    _ensure_rolling_slot_window_cached()
    user_uuid = _uuid_from_user(request.user)
    _release_expired_pending_bookings(user_uuid=user_uuid)
    now = timezone.now()

    bookings = Booking.objects.filter(user_id=user_uuid)
    confirmed_count = bookings.filter(status=BookingStatus.CONFIRMED).count()
    pending_count = bookings.filter(status=BookingStatus.PENDING).count()
    total_spent = (
        bookings.filter(payment_status=PaymentStatus.MOCK_PAID).aggregate(total=models.Sum('final_price')).get('total')
        or Decimal('0.00')
    )

    available_slots = (
        TimeSlot.objects.select_related('facility')
        .filter(
            facility__is_active=True,
            is_open=True,
            start_at__gte=now,
            current_bookings__lt=models.F('max_bookings'),
        )
        .order_by('start_at')
    )

    sport_rows = (
        available_slots.values('facility__sport_type')
        .annotate(available_slots=models.Count('id'), next_start_at=models.Min('start_at'))
        .order_by('-available_slots', 'next_start_at')
    )

    upcoming_rows = list(available_slots[:6])

    return Response(
        {
            'confirmed_count': confirmed_count,
            'pending_count': pending_count,
            'total_spent': float(total_spent),
            'sport_availability': [
                {
                    'sport_type': row['facility__sport_type'],
                    'available_slots': row['available_slots'],
                    'next_start_at': row['next_start_at'],
                }
                for row in sport_rows
            ],
            'upcoming_slots': [
                {
                    'slot_id': slot.id,
                    'facility_id': slot.facility_id,
                    'facility_name': slot.facility.name,
                    'sport_type': slot.facility.sport_type,
                    'is_indoor': slot.facility.is_indoor,
                    'start_at': slot.start_at,
                    'end_at': slot.end_at,
                    'base_price_per_hour': float(slot.facility.base_price_per_hour),
                    'current_bookings': slot.current_bookings,
                    'max_bookings': slot.max_bookings,
                }
                for slot in upcoming_rows
            ],
        }
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


def _get_supabase_client() -> Client:
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError('Supabase settings missing. Check backend/.env')
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def _sync_timeslot_to_supabase(slot):
    try:
        _upsert_timeslot_to_supabase(slot)
    except Exception:
        pass


def _upsert_timeslot_to_supabase(slot):
    supabase = _get_supabase_client()
    supabase.table(settings.SUPABASE_TIMESLOT_TABLE).upsert(
        {
            'id': int(slot.id),
            'facility_id': int(slot.facility_id),
            'start_at': slot.start_at.isoformat(),
            'end_at': slot.end_at.isoformat(),
            'max_bookings': int(slot.max_bookings),
            'current_bookings': int(slot.current_bookings),
            'is_open': bool(slot.is_open),
            'availability_state': slot.availability_state,
            'slot_version': int(slot.slot_version),
            'reservation_hold_until': slot.reservation_hold_until.isoformat() if slot.reservation_hold_until else None,
            'updated_at': timezone.now().isoformat(),
        }
    ).execute()


def _sync_booking_to_supabase(booking):
    try:
        supabase = _get_supabase_client()
        supabase.table(settings.SUPABASE_BOOKING_TABLE).upsert(
            {
                'id': booking.id,
                'status': booking.status,
                'payment_status': booking.payment_status,
                'facility_id': booking.facility_id,
                'time_slot_id': booking.time_slot_id,
                'user_id': str(booking.user_id),
                'booking_source': booking.booking_source,
                'chatbot_session_id': booking.chatbot_session_id,
                'created_at': booking.created_at.isoformat(),
                'updated_at': timezone.now().isoformat(),
            }
        ).execute()
    except Exception:
        pass


def _sync_to_supabase_async(slot=None, booking=None):
    # Keep user-facing booking flows responsive even if Supabase is slow.
    if slot is not None:
        threading.Thread(target=_sync_timeslot_to_supabase, args=(slot,), daemon=True).start()
    if booking is not None:
        threading.Thread(target=_sync_booking_to_supabase, args=(booking,), daemon=True).start()


def _sync_generated_slots_to_supabase_async(slots):
    # Generated rolling-window slots should not block request latency.
    if not slots:
        return

    def _worker(rows):
        try:
            supabase = _get_supabase_client()
            payload = [
                {
                    'id': int(slot.id),
                    'facility_id': int(slot.facility_id),
                    'start_at': slot.start_at.isoformat(),
                    'end_at': slot.end_at.isoformat(),
                    'max_bookings': int(slot.max_bookings),
                    'current_bookings': int(slot.current_bookings),
                    'is_open': bool(slot.is_open),
                    'availability_state': slot.availability_state,
                    'slot_version': int(slot.slot_version),
                    'reservation_hold_until': slot.reservation_hold_until.isoformat() if slot.reservation_hold_until else None,
                    'updated_at': timezone.now().isoformat(),
                }
                for slot in rows
            ]
            supabase.table(settings.SUPABASE_TIMESLOT_TABLE).upsert(payload).execute()
        except Exception:
            pass

    threading.Thread(target=_worker, args=(list(slots),), daemon=True).start()


def _date_bounds_for_query(date_str):
    if not date_str:
        return None, None, None
    try:
        target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
    except ValueError:
        return None, None, None

    day_start = timezone.make_aware(datetime.combine(target_date, datetime.min.time()))
    day_end = day_start + timedelta(days=1)
    return target_date, day_start, day_end


_MONTH_NAME_TO_NUM = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
}

_WEEKDAY_TO_NUM = {
    'monday': 0,
    'tuesday': 1,
    'wednesday': 2,
    'thursday': 3,
    'friday': 4,
    'saturday': 5,
    'sunday': 6,
}


def _safe_iso_date(year, month, day, today, year_explicit):
    try:
        candidate = datetime(year, month, day).date()
    except ValueError:
        return None

    # For dates without explicit year, interpret as the next upcoming occurrence.
    if not year_explicit and candidate < today:
        try:
            candidate = datetime(year + 1, month, day).date()
        except ValueError:
            return None
    return candidate.isoformat()


def _parse_explicit_date_from_text(lowered, today):
    # ISO date: 2026-04-09
    iso_match = re.search(r'\b(\d{4})-(\d{2})-(\d{2})\b', lowered)
    if iso_match:
        return _safe_iso_date(
            int(iso_match.group(1)),
            int(iso_match.group(2)),
            int(iso_match.group(3)),
            today,
            True,
        )

    # Numeric date: 09/04, 9-4, 09/04/2026
    numeric_match = re.search(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b', lowered)
    if numeric_match:
        first = int(numeric_match.group(1))
        second = int(numeric_match.group(2))
        year_raw = numeric_match.group(3)
        year_explicit = year_raw is not None
        if year_raw is None:
            year = today.year
        else:
            year = int(year_raw)
            if year < 100:
                year += 2000

        # Default to day/month interpretation.
        day, month = first, second
        if month > 12 and day <= 12:
            day, month = second, first

        return _safe_iso_date(year, month, day, today, year_explicit)

    month_pattern = r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'

    # 9th April [2026]
    day_month_match = re.search(rf'\b(\d{{1,2}})(?:st|nd|rd|th)?\s*(?:of\s+)?{month_pattern}(?:\s+(\d{{4}}))?\b', lowered)
    if day_month_match:
        day = int(day_month_match.group(1))
        month = _MONTH_NAME_TO_NUM.get(day_month_match.group(2), 0)
        year_raw = day_month_match.group(3)
        year_explicit = year_raw is not None
        year = int(year_raw) if year_raw else today.year
        if month:
            return _safe_iso_date(year, month, day, today, year_explicit)

    # April 9th [2026]
    month_day_match = re.search(rf'\b{month_pattern}\s+(\d{{1,2}})(?:st|nd|rd|th)?(?:,?\s+(\d{{4}}))?\b', lowered)
    if month_day_match:
        month = _MONTH_NAME_TO_NUM.get(month_day_match.group(1), 0)
        day = int(month_day_match.group(2))
        year_raw = month_day_match.group(3)
        year_explicit = year_raw is not None
        year = int(year_raw) if year_raw else today.year
        if month:
            return _safe_iso_date(year, month, day, today, year_explicit)

    return None


def _parse_weekday_from_text(lowered, today):
    for name, weekday in _WEEKDAY_TO_NUM.items():
        if name not in lowered:
            continue

        current = today.weekday()
        delta = (weekday - current) % 7

        if f'next {name}' in lowered:
            delta = 7 if delta == 0 else delta
        elif f'this {name}' in lowered:
            delta = 0 if delta == 0 else delta
        else:
            # Plain weekday means the next occurrence.
            delta = 7 if delta == 0 else delta

        return (today + timedelta(days=delta)).isoformat()

    return None


def _parse_day_only_from_text(lowered, today):
    # Handles prompts like "on 9th" or "on 09".
    day_match = re.search(r'\bon\s+(\d{1,2})(?:st|nd|rd|th)?\b', lowered)
    if not day_match:
        return None

    day = int(day_match.group(1))
    if day < 1 or day > 31:
        return None

    current_month = _safe_iso_date(today.year, today.month, day, today, False)
    if current_month:
        candidate = datetime.strptime(current_month, '%Y-%m-%d').date()
        if candidate >= today:
            return current_month

    # Roll to next month when current month day has passed.
    month_anchor = (datetime(today.year, today.month, 1) + timedelta(days=32)).date().replace(day=1)
    return _safe_iso_date(month_anchor.year, month_anchor.month, day, today, False)


def _normalize_text(value):
    return re.sub(r'[^a-z0-9]+', ' ', (value or '').lower()).strip()


def _active_facility_names_cached():
    cache_key = 'chat:active-facility-names:v1'
    rows = cache.get(cache_key)
    if rows is not None:
        return rows

    rows = [row['name'] for row in _active_facility_rows_cached()]
    cache.set(cache_key, rows, timeout=60 * 5)
    return rows


def _active_facility_rows_cached():
    cache_key = 'chat:active-facility-rows:v1'
    rows = cache.get(cache_key)
    if rows is not None:
        return rows

    rows = list(
        Facility.objects.filter(is_active=True)
        .values('id', 'name', 'sport_type', 'is_indoor')
        .order_by('name')
    )
    cache.set(cache_key, rows, timeout=60 * 5)
    return rows


def _resolve_active_facility_from_hint(hint, strict=False):
    normalized_hint = _normalize_text(hint)
    if not normalized_hint:
        return None

    hint_compact = normalized_hint.replace(' ', '')
    hint_tokens = [token for token in normalized_hint.split() if len(token) >= 3]
    strict_ignore_tokens = {
        'arena',
        'court',
        'table',
        'field',
        'club',
        'center',
        'centre',
        'sport',
        'sports',
        'indoor',
        'outdoor',
        'football',
        'billiard',
        'pickleball',
        'volleyball',
        'basketball',
        'futsal',
        'tennis',
        'badminton',
        'book',
        'reserve',
        'slot',
        'slots',
        'today',
        'tomorrow',
    }
    strict_tokens = [token for token in hint_tokens if token not in strict_ignore_tokens]
    rows = _active_facility_rows_cached()

    best = None
    best_score = -1
    strict_best = None
    strict_best_hits = -1
    best_ratio = 0.0
    second_best_ratio = 0.0
    best_ratio_row = None
    for row in rows:
        normalized_name = _normalize_text(row.get('name'))
        if not normalized_name:
            continue
        name_compact = normalized_name.replace(' ', '')

        if hint_compact and (hint_compact in name_compact or name_compact in hint_compact):
            return row

        token_hits = 0
        for token in normalized_name.split():
            if len(token) < 3:
                continue
            if token in strict_ignore_tokens:
                continue
            if token in normalized_hint:
                token_hits += 1

        if token_hits > best_score:
            best_score = token_hits
            best = row

        if strict_tokens:
            strict_hits = sum(1 for token in strict_tokens if token in normalized_name)
            if strict_hits > strict_best_hits:
                strict_best_hits = strict_hits
                strict_best = row

        ratio = max(
            SequenceMatcher(None, normalized_hint, normalized_name).ratio(),
            SequenceMatcher(None, hint_compact, normalized_name.replace(' ', '')).ratio(),
        )
        if ratio > best_ratio:
            second_best_ratio = best_ratio
            best_ratio = ratio
            best_ratio_row = row
        elif ratio > second_best_ratio:
            second_best_ratio = ratio

    if strict:
        if strict_tokens:
            if strict_best_hits == len(strict_tokens):
                return strict_best
            return None
        if best_score >= 2:
            return best
        return None

    # Non-strict matching should still be conservative to avoid wrong-venue jumps.
    if strict_tokens and best_score >= max(1, len(strict_tokens) - 1) and best_ratio >= 0.78:
        return best

    # Accept fuzzy match only when confidence is high and clearly better than alternatives.
    if best_ratio_row is not None and best_ratio >= 0.86 and (best_ratio - second_best_ratio) >= 0.04:
        return best_ratio_row
    return None


def _extract_facility_hint_from_message(message):
    normalized = _normalize_text(message)
    if not normalized:
        return None

    # Prefer phrases after common venue prepositions.
    patterns = [
        r'\b(?:at|in|for)\s+([a-z0-9\s\-&]+)',
    ]
    stop_tokens = {
        'today',
        'tomorrow',
        'tonight',
        'evening',
        'afternoon',
        'morning',
        'on',
        'around',
        'from',
        'to',
        'for',
        'book',
        'booking',
        'slot',
        'slots',
        'available',
        'availability',
    }

    for pattern in patterns:
        m = re.search(pattern, normalized)
        if not m:
            continue
        phrase = _normalize_text(m.group(1))
        if not phrase:
            continue
        tokens = []
        for token in phrase.split():
            if token in stop_tokens:
                break
            # Stop before time indicators like 7pm / 18:00.
            if re.match(r'^\d{1,2}(?::\d{2})?(am|pm)?$', token):
                break
            tokens.append(token)

        hint = ' '.join(tokens).strip()
        if hint:
            return hint

    # Also handle direct prompts without prepositions, e.g. "book blue chalk billiard lounge today 9pm".
    generic_lead = re.sub(r'^\b(?:book|booking|reserve|reservation|find|show|list|available|slots?|please)\b\s*', '', normalized)
    if generic_lead:
        tokens = []
        for token in generic_lead.split():
            if token in stop_tokens:
                break
            if token in {'hour', 'hours', 'hr', 'hrs'}:
                break
            if re.match(r'^\d+$', token):
                break
            if re.match(r'^\d{1,2}(?::\d{2})?(am|pm)?$', token):
                break
            tokens.append(token)

        hint = ' '.join(tokens).strip()
        if hint and len(hint.split()) >= 2:
            return hint

    return None


def _find_facility_name_in_message(message):
    hint = _extract_facility_hint_from_message(message)
    if hint:
        resolved = _resolve_active_facility_from_hint(hint, strict=True)
        if resolved:
            return resolved.get('name')

    # Fallback to non-strict matching, prioritizing extracted hint first.
    if hint:
        resolved = _resolve_active_facility_from_hint(hint, strict=False)
        if resolved:
            return resolved.get('name')

    resolved = _resolve_active_facility_from_hint(message, strict=False)
    if resolved:
        return resolved.get('name')
    return None


def _chatbot_cache_revision():
    cache_key = 'chat:cache-revision:v1'
    cached = cache.get(cache_key)
    if cached:
        return cached

    latest_slot = TimeSlot.objects.order_by('-updated_at').values_list('updated_at', flat=True).first()
    latest_facility = Facility.objects.order_by('-updated_at').values_list('updated_at', flat=True).first()
    slot_part = int(latest_slot.timestamp()) if latest_slot is not None else 0
    facility_part = int(latest_facility.timestamp()) if latest_facility is not None else 0
    revision = f'{slot_part}:{facility_part}'
    cache.set(cache_key, revision, timeout=30)
    return revision


def _conversation_cache_key(user_uuid, chatbot_session_id):
    session_part = chatbot_session_id.strip().lower() if chatbot_session_id else 'default'
    return f'chat:ctx:{str(user_uuid)}:{session_part}'


def _load_chat_context(user_uuid, chatbot_session_id):
    return cache.get(_conversation_cache_key(user_uuid, chatbot_session_id)) or {}


def _save_chat_context(user_uuid, chatbot_session_id, extracted):
    payload = {
        'sport_type': extracted.get('sport_type'),
        'date': extracted.get('date'),
        'start_time': extracted.get('start_time'),
        'end_time': extracted.get('end_time'),
        'duration_hours': extracted.get('duration_hours'),
        'facility_name': extracted.get('facility_name'),
    }
    cache.set(_conversation_cache_key(user_uuid, chatbot_session_id), payload, timeout=60 * 60)


def _merge_with_chat_context(extracted, chat_context):
    merged = dict(extracted or {})
    for key in ['sport_type', 'date', 'start_time', 'end_time', 'duration_hours', 'facility_name']:
        value = merged.get(key)
        if value in [None, '', 'unknown']:
            merged[key] = chat_context.get(key)
    return merged


def _parse_time_fragment(fragment):
    text = (fragment or '').strip().lower()
    if not text:
        return None

    m = re.match(r'^(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)$', text)
    if m:
        hour = int(m.group(1))
        minute = int(m.group(2) or 0)
        meridiem = m.group(3)
        if meridiem == 'pm' and hour != 12:
            hour += 12
        if meridiem == 'am' and hour == 12:
            hour = 0
        return f'{hour:02d}:{minute:02d}'

    m = re.match(r'^([01]?\d|2[0-3]):([0-5]\d)$', text)
    if m:
        return f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"

    m = re.match(r'^([01]?\d|2[0-3])$', text)
    if m:
        return f"{int(m.group(1)):02d}:00"

    return None


def _extract_time_range_from_text(lowered):
    patterns = [
        r'\bstarting\s+from\s+([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\s+to\s+([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\b',
        r'\bfrom\s+([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\s+to\s+([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\b',
        r'\bfrom\s+([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\s*[-~]\s*([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\b',
        r'\bstart(?:ing)?\s+(?:at\s+)?([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\s+(?:and\s+)?end(?:ing)?\s+(?:at\s+)?([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\b',
        r'\b([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\s*[-~]\s*([0-2]?\d(?::[0-5]\d)?\s*(?:am|pm)?)\b',
    ]
    for pattern in patterns:
        m = re.search(pattern, lowered)
        if not m:
            continue
        start = _parse_time_fragment(m.group(1))
        end = _parse_time_fragment(m.group(2))
        if start and end:
            return start, end
    return None, None


def _call_ai_extractor(message):
    system_prompt = (
        'You extract booking entities for a sports app. '
        'Output strict JSON with keys: intent, sport_type, is_indoor, date, start_time, duration_hours, reference_option_index. '
        'intent in [search, confirm, cancel, unknown]. '
        'sport_type in [football, billiard, pickleball, volleyball, basketball, futsal, tennis, badminton] or null. '
        'is_indoor true/false/null. date YYYY-MM-DD or null. start_time HH:MM (24h) or null. '
        'duration_hours number or null. reference_option_index integer or null.'
    )

    try:
        if settings.GROQ_API_KEY:
            payload = {
                'model': 'llama-3.1-8b-instant',
                'temperature': 0.1,
                'messages': [
                    {'role': 'system', 'content': system_prompt},
                    {'role': 'user', 'content': message},
                ],
                'response_format': {'type': 'json_object'},
            }
            headers = {'Authorization': f'Bearer {settings.GROQ_API_KEY}', 'Content-Type': 'application/json'}
            response = requests.post('https://api.groq.com/openai/v1/chat/completions', headers=headers, json=payload, timeout=8)
            response.raise_for_status()
            content = response.json()['choices'][0]['message']['content']
            return json.loads(content)

        if settings.HF_API_KEY:
            prompt = f'{system_prompt}\nUser: {message}\nJSON:'
            headers = {'Authorization': f'Bearer {settings.HF_API_KEY}'}
            payload = {'inputs': prompt, 'parameters': {'max_new_tokens': 180, 'temperature': 0.1}}
            response = requests.post(
                'https://api-inference.huggingface.co/models/mistralai/Mixtral-8x7B-Instruct-v0.1',
                headers=headers,
                json=payload,
                timeout=12,
            )
            response.raise_for_status()
            out = response.json()
            generated = out[0]['generated_text'] if isinstance(out, list) else out.get('generated_text', '')
            start = generated.find('{')
            end = generated.rfind('}')
            if start >= 0 and end > start:
                return json.loads(generated[start : end + 1])
    except Exception:
        pass

    return {
        'intent': 'unknown',
        'sport_type': None,
        'is_indoor': None,
        'date': None,
        'start_time': None,
        'duration_hours': None,
        'reference_option_index': None,
    }


def _rain_mm(lat, lng, date_str):
    response = requests.get(
        'https://api.open-meteo.com/v1/forecast',
        params={
            'latitude': lat,
            'longitude': lng,
            'hourly': 'precipitation',
            'start_date': date_str,
            'end_date': date_str,
            'timezone': 'auto',
        },
        timeout=10,
    )
    response.raise_for_status()
    hourly = response.json().get('hourly', {}).get('precipitation', [])
    return float(max(hourly)) if hourly else 0.0


def _cached_rain_mm(lat, lng, date_str):
    # Weather calls are expensive; cache by location/date to keep chat suggestions snappy.
    cache_key = f'rain:{round(float(lat), 3)}:{round(float(lng), 3)}:{date_str}'
    cached = cache.get(cache_key)
    if cached is not None:
        return float(cached)

    rain = _rain_mm(lat, lng, date_str)
    cache.set(cache_key, rain, timeout=60 * 30)
    return rain


SPORT_FAQ = {
    'football': {
        'overview': 'Football venues are best for 60-120 minute sessions. Outdoor fields may get weather discounts when rain is high.',
        'equipment': 'Bring boots, shin guards, and team bibs. Water-resistant balls are recommended in rainy weather.',
        'field_size': '5v5 pitches are commonly about 25m x 16m to 42m x 25m. 7v7 fields are larger and vary by venue.',
        'rules': 'Standard match format is 11v11, but most social bookings are 5v5 or 7v7. Confirm field size before booking.',
        'tips': 'Warm up 10 minutes, rotate substitutes every 8-10 minutes, and hydrate between sets.',
    },
    'billiard': {
        'overview': 'Billiard clubs are indoor and usually book in 1-2 hour blocks with single-table capacity controls.',
        'equipment': 'Cue sticks are usually available at the club; bring your own chalk and glove for consistency.',
        'field_size': 'Common table sizes are 7ft, 8ft, and 9ft depending on club setup and game format.',
        'rules': 'Most clubs support 8-ball and 9-ball house rules. Ask for table rule sheet before play starts.',
        'tips': 'Use straight warm-up shots first, then set break routine to improve consistency.',
    },
    'pickleball': {
        'overview': 'Pickleball courts are ideal for 1 hour sessions and often have shared capacity for doubles rotations.',
        'equipment': 'Bring paddle, non-marking shoes, and indoor balls when booking indoor courts.',
        'field_size': 'Standard court size is 13.41m x 6.10m (44ft x 20ft), same footprint as doubles badminton.',
        'rules': 'Social games usually play to 11 points, win by 2. Kitchen faults are the most common beginner error.',
        'tips': 'Practice soft dinks and third-shot drops to control rallies.',
    },
    'volleyball': {
        'overview': 'Volleyball venues support team sessions and are best reserved in 2-hour windows for full matches.',
        'equipment': 'Bring court shoes, knee pads, and match ball. Team rosters are helpful for smooth check-in.',
        'field_size': 'Indoor volleyball courts are typically 18m x 9m with free zone clearance around boundaries.',
        'rules': 'Indoor games typically use rally scoring to 25 points per set. Confirm court and net height on arrival.',
        'tips': 'Assign server-receive lanes before starting to reduce confusion.',
    },
    'basketball': {
        'overview': 'Basketball clubs can be indoor or outdoor and usually support multiple concurrent bookings per slot.',
        'equipment': 'Bring indoor/outdoor shoes and your own ball if you prefer a specific grip.',
        'field_size': 'Full courts are around 28m x 15m (FIBA), while training sessions may use half-court setups.',
        'rules': 'Most booking sessions run half-court 3v3 or full-court 5v5 depending on player count.',
        'tips': 'Use 5-minute shooting warmup and dynamic stretching before scrimmage.',
    },
    'futsal': {
        'overview': 'Futsal venues are fast-paced and commonly reserved in 1-2 hour sessions for 5v5 matches.',
        'equipment': 'Use futsal shoes, shin guards, and a low-bounce futsal ball.',
        'field_size': 'Typical futsal courts are around 40m x 20m, but community venues may use smaller variants.',
        'rules': 'Rolling substitutions are common and keep game intensity high. Confirm local foul accumulation rules.',
        'tips': 'Short passing triangles and quick transitions are key for beginner teams.',
    },
    'tennis': {
        'overview': 'Tennis courts can be reserved for singles or doubles and are usually priced hourly per court.',
        'equipment': 'Bring racket, tennis shoes, and balls. For outdoor courts, check weather before booking.',
        'field_size': 'A doubles court is 23.77m x 10.97m, while singles uses the same length with narrower sidelines.',
        'rules': 'Recreational sessions usually follow one-set or timed format. Tie-break at 6-6 is common.',
        'tips': 'Spend first 10 minutes on cooperative rally and serve rhythm.',
    },
    'badminton': {
        'overview': 'Badminton halls are mostly indoor and ideal for one-hour sessions with high turnover slots.',
        'equipment': 'Bring racket, non-marking shoes, and shuttles suitable for indoor airflow.',
        'field_size': 'Doubles courts are 13.4m x 6.1m; singles use the same length but narrower side boundaries.',
        'rules': 'Rally scoring to 21 points, win by 2. Many halls enforce non-marking shoe policy.',
        'tips': 'Rotate doubles partners every game for balanced practice.',
    },
}

GENERAL_FAQ = {
    'booking': 'To book fast: tell sport, date, start time, and duration. Example: book indoor badminton tomorrow 8pm for 1 hour.',
    'payment': 'Bookings are confirmed only after payment status becomes paid. Pending payments hold slots temporarily.',
    'cancellation': 'You can cancel upcoming bookings from Booking History. Cancelled slots become available again.',
    'refund': 'For mock payments, refunds are simulated by support/admin workflows. Real gateway refunds depend on provider policy.',
    'pricing': 'Final price may include weather or low-occupancy discounts depending on slot and sport conditions.',
    'checkin': 'Arrive 10-15 minutes early for equipment setup and identity verification at venue check-in.',
    'safety': 'Wear proper sport shoes, hydrate, warm up before play, and follow venue supervision rules.',
}


def _find_sport_in_message(message):
    lowered = message.lower()
    for sport in SPORT_FAQ.keys():
        if sport in lowered:
            return sport
    return None


def _looks_like_venue_faq(lowered):
    venue_tokens = ['venue', 'court', 'field', 'table', 'location', 'address', 'contact', 'phone', 'whatsapp']
    pricing_tokens = ['price', 'pricing', 'cost', 'rate', 'how much', 'fee']
    return any(token in lowered for token in venue_tokens + pricing_tokens)


def _fake_venue_contact(facility):
    slug = re.sub(r'[^a-z0-9]+', '', (facility.name or '').lower())
    if not slug:
        slug = f'venue{facility.id}'

    base_num = (int(facility.id) * 37) % 9000 + 1000
    tail_num = (int(facility.id) * 53) % 9000 + 1000
    return {
        'phone': f'+60-3-{base_num:04d}-{tail_num:04d}',
        'email': f'hello@{slug}.sports.example',
    }


def _venue_faq_answer(message):
    lowered = message.lower()
    facility_name = _find_facility_name_in_message(message)

    if not _looks_like_venue_faq(lowered) and not facility_name:
        return None

    facilities_qs = Facility.objects.filter(is_active=True)
    target_rows = []

    if facility_name:
        target_rows = list(facilities_qs.filter(name=facility_name)[:1])
        if not target_rows:
            normalized_hint = _normalize_text(facility_name)
            normalized_hint_compact = normalized_hint.replace(' ', '')
            rows = list(facilities_qs[:50])
            for row in rows:
                normalized_name = _normalize_text(row.name)
                if normalized_hint_compact and normalized_hint_compact in normalized_name.replace(' ', ''):
                    target_rows = [row]
                    break

    if not target_rows:
        if 'all venue' in lowered or 'all venues' in lowered:
            target_rows = list(facilities_qs.order_by('name')[:6])
        elif _looks_like_venue_faq(lowered):
            target_rows = list(facilities_qs.order_by('name')[:3])

    if not target_rows:
        return {
            'type': 'faq_answer',
            'sport_type': None,
            'text': 'I could not find that venue. Try asking with another venue name.',
        }

    lines = []
    for venue in target_rows:
        contact = _fake_venue_contact(venue)
        lines.append(
            (
                f"- {venue.name}: {venue.location_name} | "
                f"Price: USD {Decimal(str(venue.base_price_per_hour)).quantize(Decimal('0.01'))}/hour | "
                f"Contact: {contact['phone']} | Email: {contact['email']}"
            )
        )

    scope_text = 'Venue FAQ' if len(target_rows) == 1 else 'Venue FAQ (Top Matches)'
    return {
        'type': 'faq_answer',
        'sport_type': target_rows[0].sport_type if len(target_rows) == 1 else None,
        'text': f"{scope_text}\n" + '\n'.join(lines),
    }


def _faq_answer(message):
    lowered = message.lower()
    venue_payload = _venue_faq_answer(message)
    if venue_payload is not None:
        return venue_payload

    faq_keywords = ['faq', 'rule', 'rules', 'how to play', 'what is', 'equipment', 'tips']
    if not any(keyword in lowered for keyword in faq_keywords):
        return None

    sport = _find_sport_in_message(lowered)
    if sport:
        data = SPORT_FAQ[sport]
        wants_rules = any(token in lowered for token in ['rule', 'rules', 'how to play', 'what is'])
        wants_equipment = any(token in lowered for token in ['equipment', 'gear', 'racket', 'boots', 'shoes'])
        wants_tips = any(token in lowered for token in ['tips', 'beginner', 'improve', 'training', 'practice'])
        wants_field = any(
            token in lowered for token in ['field', 'court', 'table size', 'dimensions', 'size']
        )

        focus = []
        if wants_rules:
            focus.append(f"- Rules: {data['rules']}")
        if wants_equipment:
            focus.append(f"- Equipment: {data['equipment']}")
        if wants_tips:
            focus.append(f"- Tips: {data['tips']}")
        if wants_field:
            focus.append(f"- Field/Court: {data['field_size']}")
        if not focus:
            focus = [
                f"- Overview: {data['overview']}",
                f"- Rules: {data['rules']}",
                f"- Equipment: {data['equipment']}",
                f"- Tips: {data['tips']}",
                f"- Field/Court: {data['field_size']}",
            ]

        return {
            'type': 'faq_answer',
            'sport_type': sport,
            'text': f"{sport.title()} FAQ\n" + '\n'.join(focus),
        }

    for topic, answer in GENERAL_FAQ.items():
        if topic in lowered:
            return {
                'type': 'faq_answer',
                'sport_type': None,
                'text': f'{topic.title()} FAQ\n- {answer}',
            }

    if any(token in lowered for token in ['pay', 'checkout', 'confirm payment']):
        return {
            'type': 'faq_answer',
            'sport_type': None,
            'text': f"Payment FAQ\n- {GENERAL_FAQ['payment']}",
        }

    if any(token in lowered for token in ['cancel', 'reschedule']):
        return {
            'type': 'faq_answer',
            'sport_type': None,
            'text': f"Cancellation FAQ\n- {GENERAL_FAQ['cancellation']}",
        }

    supported = ', '.join([name.title() for name in SPORT_FAQ.keys()])
    general_topics = ', '.join([topic.title() for topic in GENERAL_FAQ.keys()])
    return {
        'type': 'faq_answer',
        'sport_type': None,
        'text': (
            f'We support sports FAQs for: {supported}. '
            f'General topics: {general_topics}. '
            'Ask for example: football field size, tennis equipment, booking faq, or payment faq.'
        ),
    }


def _keyword_intent_hint(message):
    lowered = (message or '').lower().strip()
    if not lowered:
        return 'unknown'

    booking_keywords = [
        'book',
        'booking',
        'reserve',
        'reservation',
        'available slot',
        'available slots',
        'slot available',
        'slots available',
        'availability',
        'find slot',
        'find slots',
        'time slot',
        'timeslot',
        'open slot',
        'free slot',
        'next slot',
        'show slots',
        'available at',
        'slots at',
        'venue slots',
    ]
    if any(keyword in lowered for keyword in booking_keywords):
        return 'search'

    # If the user mentions a sport and timing context, treat as booking intent.
    has_sport = _find_sport_in_message(lowered) is not None
    has_time_context = any(token in lowered for token in ['today', 'tomorrow', 'am', 'pm', ':'])
    if has_sport and has_time_context:
        return 'search'

    question_tokens = [
        '?',
        'what',
        'how',
        'when',
        'where',
        'which',
        'why',
        'rules',
        'tips',
        'equipment',
        'price',
        'cost',
        'location',
        'contact',
        'payment',
        'cancellation',
        'refund',
        'faq',
    ]
    if any(token in lowered for token in question_tokens):
        return 'faq'

    return 'unknown'


def _fallback_extract_from_message(message):
    lowered = message.lower().strip()
    today = timezone.localdate()

    intent = 'unknown'
    if any(token in lowered for token in ['cancel', 'remove booking']):
        intent = 'cancel'
    elif any(token in lowered for token in ['confirm', 'book this', 'pay now']):
        intent = 'confirm'
    elif any(token in lowered for token in ['book the last one', 'book last one', 'book first one', 'reserve the last one', 'reserve last one']):
        intent = 'confirm'
    elif any(token in lowered for token in ['book', 'reserve', 'find slot', 'search', 'how about', 'available', 'another', 'same place', 'same time', 'next', 'this']):
        intent = 'search'

    sport_type = None
    for sport in SPORT_FAQ.keys():
        if sport in lowered:
            sport_type = sport
            break

    # Indoor/outdoor filtering is intentionally disabled for chatbot queries.
    is_indoor = None

    date_value = None
    if 'tomorrow' in lowered or re.search(r'\btmr\b|\btmw\b|\btom\b', lowered):
        date_value = (today + timedelta(days=1)).isoformat()
    elif 'today' in lowered or 'tonight' in lowered or 'this evening' in lowered:
        date_value = today.isoformat()
    else:
        date_value = _parse_explicit_date_from_text(lowered, today)
        if date_value is None:
            date_value = _parse_weekday_from_text(lowered, today)
        if date_value is None:
            date_value = _parse_day_only_from_text(lowered, today)

    start_time = None
    ampm = re.search(r'\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)\b', lowered)
    if ampm:
        hour = int(ampm.group(1))
        minute = int(ampm.group(2) or 0)
        meridiem = ampm.group(3)
        if meridiem == 'pm' and hour != 12:
            hour += 12
        if meridiem == 'am' and hour == 12:
            hour = 0
        start_time = f'{hour:02d}:{minute:02d}'
    else:
        twenty_four = re.search(r'\b([01]?\d|2[0-3]):([0-5]\d)\b', lowered)
        if twenty_four:
            start_time = f'{int(twenty_four.group(1)):02d}:{int(twenty_four.group(2)):02d}'
        else:
            loose_hour = re.search(r'\b(?:at|around)\s*(\d{1,2})\b', lowered)
            if loose_hour:
                hour = int(loose_hour.group(1))
                if 0 <= hour <= 23:
                    if hour <= 8 and not any(token in lowered for token in ['am', 'morning']):
                        hour += 12
                    start_time = f'{hour:02d}:00'

    if start_time is None and any(token in lowered for token in ['tonight', 'this evening', 'evening']):
        start_time = '18:00'
    if start_time is None and 'this afternoon' in lowered:
        start_time = '15:00'

    duration_hours = None
    duration_match = re.search(r'\b(\d+(?:\.\d+)?)\s*(hour|hours|hr|hrs)\b', lowered)
    if duration_match:
        duration_hours = float(duration_match.group(1))

    end_time = None
    range_start, range_end = _extract_time_range_from_text(lowered)
    if range_start and range_end:
        start_time = range_start
        end_time = range_end
        try:
            start_hour, start_minute = [int(x) for x in start_time.split(':')]
            end_hour, end_minute = [int(x) for x in end_time.split(':')]
            start_minutes = start_hour * 60 + start_minute
            end_minutes = end_hour * 60 + end_minute
            if end_minutes > start_minutes:
                duration_hours = round((end_minutes - start_minutes) / 60, 2)
        except Exception:
            pass

    # Convert "7pm for 2 hours" to a search window (19:00 -> 21:00).
    if end_time is None and start_time and duration_hours and float(duration_hours) > 1:
        try:
            start_hour, start_minute = [int(x) for x in start_time.split(':')]
            start_minutes = start_hour * 60 + start_minute
            end_minutes = start_minutes + int(round(float(duration_hours) * 60))
            if end_minutes <= 24 * 60:
                end_hour = end_minutes // 60
                end_minute = end_minutes % 60
                end_time = f'{end_hour:02d}:{end_minute:02d}'
        except Exception:
            pass

    reference_option_index = None
    if intent in ['confirm', 'unknown']:
        if any(token in lowered for token in ['the last one', 'last one', 'last slot', 'last option']):
            reference_option_index = -1
            intent = 'confirm'
        elif any(token in lowered for token in ['the first one', 'first one', 'first slot', 'first option']):
            reference_option_index = 1
            intent = 'confirm'
        else:
            m = re.search(r'\b(?:number|no\.?|option|slot)\s*(\d{1,3})\b', lowered)
            if m:
                reference_option_index = int(m.group(1))
                intent = 'confirm'

    facility_name = _find_facility_name_in_message(message)

    if intent == 'search':
        if date_value is None:
            date_value = (today + timedelta(days=1)).isoformat()
        if start_time is None:
            start_time = '18:00'
        if duration_hours is None:
            duration_hours = 1.0

    if intent == 'unknown' and sport_type and (date_value or start_time or duration_hours):
        intent = 'search'
        if date_value is None:
            date_value = (today + timedelta(days=1)).isoformat()
        if start_time is None:
            start_time = '18:00'
        if duration_hours is None:
            duration_hours = 1.0

    if intent == 'unknown' and facility_name and (date_value or start_time or duration_hours):
        intent = 'search'
        if date_value is None:
            date_value = (today + timedelta(days=1)).isoformat()
        if start_time is None:
            start_time = '18:00'
        if duration_hours is None:
            duration_hours = 1.0

    return {
        'intent': intent,
        'sport_type': sport_type,
        'is_indoor': is_indoor,
        'date': date_value,
        'start_time': start_time,
        'end_time': end_time,
        'duration_hours': duration_hours,
        'reference_option_index': reference_option_index,
        'facility_name': facility_name,
    }


def _merge_extracted(primary, fallback):
    merged = dict(primary or {})
    for key in [
        'intent',
        'sport_type',
        'is_indoor',
        'date',
        'start_time',
        'end_time',
        'duration_hours',
        'reference_option_index',
        'facility_name',
    ]:
        value = merged.get(key)
        if value in [None, '', 'unknown']:
            merged[key] = fallback.get(key)
    return merged


def _create_pending_booking(target, user_uuid, booking_source=BookingSource.MANUAL, chatbot_session_id=''):
    option_id = str(target.get('option_id') or '').strip()
    if ':' not in option_id:
        raise ValueError('Invalid option selected.')
    chunks = option_id.split(':')
    if len(chunks) < 2:
        raise ValueError('Invalid option selected.')

    facility_id = chunks[0]
    slot_id = chunks[1]
    duration_hours = Decimal(str(target.get('duration_hours', 1) or 1))

    with transaction.atomic():
        slot = TimeSlot.objects.select_for_update().get(id=slot_id, facility_id=facility_id, is_open=True)
        already_booked = Booking.objects.filter(
            user_id=user_uuid,
            time_slot_id=slot.id,
        ).exclude(status=BookingStatus.CANCELLED).exists()
        if already_booked:
            raise ValueError('You already booked this slot.')

        # Enforce single active booking per slot across all accounts.
        slot_taken = Booking.objects.filter(time_slot_id=slot.id).exclude(status=BookingStatus.CANCELLED).exists()
        if slot_taken:
            raise ValueError('Slot no longer available.')

        if slot.current_bookings >= slot.max_bookings:
            raise ValueError('Slot no longer available.')

        slot.current_bookings += 1
        slot.reservation_hold_until = timezone.now() + timedelta(minutes=PAYMENT_WINDOW_MINUTES)
        slot.is_open = False
        slot.save(update_fields=['current_bookings', 'reservation_hold_until', 'is_open', 'availability_state', 'updated_at'])

        booking = Booking.objects.create(
            user_id=user_uuid,
            facility_id=facility_id,
            time_slot=slot,
            start_at=slot.start_at,
            end_at=slot.end_at,
            duration_hours=duration_hours,
            status=BookingStatus.PENDING,
            payment_status=PaymentStatus.MOCK_PENDING,
            base_price=Decimal(str(target.get('base_price') or target.get('final_price') or '0')),
            weather_discount=Decimal(str(target.get('weather_discount') or '0')),
            empty_slot_discount=Decimal(str(target.get('empty_slot_discount') or '0')),
            final_price=Decimal(str(target.get('final_price') or target.get('base_price') or '0')),
            weather_rain_mm=float(target.get('rain_mm', 0.0)),
            booking_source=booking_source,
            chatbot_session_id=chatbot_session_id or '',
        )

    _sync_to_supabase_async(slot=slot, booking=booking)
    return booking


def _payment_deadline_for_booking(booking):
    created_at = booking.created_at
    if created_at is None:
        return timezone.now()
    if timezone.is_naive(created_at):
        created_at = timezone.make_aware(created_at, dt_timezone.utc)
    return created_at + timedelta(minutes=PAYMENT_WINDOW_MINUTES)


def _release_expired_pending_bookings(user_uuid=None, booking_ids=None):
    cutoff = timezone.now() - timedelta(minutes=PAYMENT_WINDOW_MINUTES)
    qs = Booking.objects.filter(
        status=BookingStatus.PENDING,
        payment_status=PaymentStatus.MOCK_PENDING,
        created_at__lte=cutoff,
    )
    if user_uuid is not None:
        qs = qs.filter(user_id=user_uuid)
    if booking_ids:
        qs = qs.filter(id__in=booking_ids)

    expired_bookings = list(qs)
    if not expired_bookings:
        return []

    released = []
    with transaction.atomic():
        for booking in expired_bookings:
            locked_booking = Booking.objects.select_for_update().get(id=booking.id)
            if locked_booking.status != BookingStatus.PENDING or locked_booking.payment_status != PaymentStatus.MOCK_PENDING:
                continue

            slot = TimeSlot.objects.select_for_update().get(id=locked_booking.time_slot_id)
            if slot.current_bookings > 0:
                slot.current_bookings -= 1
            slot.reservation_hold_until = None
            slot.is_open = slot.current_bookings == 0
            slot.save(update_fields=['current_bookings', 'reservation_hold_until', 'is_open', 'availability_state', 'updated_at'])

            locked_booking.status = BookingStatus.CANCELLED
            locked_booking.payment_status = PaymentStatus.MOCK_FAILED
            locked_booking.notes = ((locked_booking.notes or '') + ' [Auto-cancelled: payment window expired]').strip()
            locked_booking.save(update_fields=['status', 'payment_status', 'notes', 'updated_at'])
            released.append((slot, locked_booking))

    for slot, booking in released:
        _sync_to_supabase_async(slot=slot, booking=booking)

    return [booking.id for _, booking in released]


def _target_option_chunks(target):
    option_id = str(target.get('option_id') or '').strip()
    if ':' not in option_id:
        raise ValueError('Invalid option selected.')
    chunks = option_id.split(':')
    if len(chunks) < 2:
        raise ValueError('Invalid option selected.')
    slot_ids = [chunk.strip() for chunk in str(chunks[1]).split('+') if chunk.strip()]
    if not slot_ids:
        raise ValueError('Invalid option selected.')
    return chunks[0], slot_ids


def _is_target_currently_available(target):
    try:
        facility_id, slot_ids = _target_option_chunks(target)
    except ValueError:
        return False

    slots = list(
        TimeSlot.objects.filter(id__in=slot_ids, facility_id=facility_id, is_open=True).order_by('start_at')
    )
    if len(slots) != len(slot_ids):
        return False

    slot_map = {str(slot.id): slot for slot in slots}
    ordered = []
    for sid in slot_ids:
        slot = slot_map.get(str(sid))
        if slot is None:
            return False
        ordered.append(slot)

    for i in range(1, len(ordered)):
        if ordered[i - 1].end_at != ordered[i].start_at:
            return False

    for slot in ordered:
        if Booking.objects.filter(time_slot_id=slot.id).exclude(status=BookingStatus.CANCELLED).exists():
            return False
        if slot.current_bookings >= slot.max_bookings:
            return False
        if slot.reservation_hold_until and slot.reservation_hold_until > timezone.now():
            return False
    return True


def _canonicalize_target_for_quote(target):
    if not isinstance(target, dict):
        return target

    try:
        facility_id, slot_ids = _target_option_chunks(target)
    except ValueError:
        return target

    slots = list(
        TimeSlot.objects.select_related('facility').filter(id__in=slot_ids, facility_id=facility_id).order_by('start_at')
    )
    if len(slots) != len(slot_ids):
        return target

    slot_map = {str(slot.id): slot for slot in slots}
    ordered_slots = []
    for sid in slot_ids:
        slot = slot_map.get(str(sid))
        if slot is None:
            return target
        ordered_slots.append(slot)

    for i in range(1, len(ordered_slots)):
        if ordered_slots[i - 1].end_at != ordered_slots[i].start_at:
            return target

    slot = ordered_slots[0]
    bundle_start = ordered_slots[0].start_at
    bundle_end = ordered_slots[-1].end_at
    slot_hours = Decimal((bundle_end - bundle_start).total_seconds() / 3600).quantize(Decimal('0.01'))
    try:
        requested_hours = Decimal(str(target.get('duration_hours') or slot_hours)).quantize(Decimal('0.01'))
    except Exception:
        requested_hours = slot_hours

    if requested_hours <= Decimal('0.00') or requested_hours > slot_hours:
        requested_hours = slot_hours

    total_base = Decimal('0.00')
    total_weather = Decimal('0.00')
    total_empty = Decimal('0.00')
    total_final = Decimal('0.00')
    rain_mm = 0.0
    for s in ordered_slots:
        occupancy = (Decimal(int(s.current_bookings)) / Decimal(int(s.max_bookings))) if int(s.max_bookings) > 0 else Decimal('1.00')
        rain = 0.0
        if not s.facility.is_indoor:
            try:
                rain = float(_cached_rain_mm(s.facility.latitude, s.facility.longitude, s.start_at.date().isoformat()))
            except Exception:
                rain = 0.0
        p = Booking.compute_dynamic_price(
            base_price_per_hour=s.facility.base_price_per_hour,
            duration_hours=Decimal('1.00'),
            is_indoor=s.facility.is_indoor,
            rain_mm=rain,
            occupancy_rate=float(occupancy),
        )
        total_base += Decimal(str(p['base_price']))
        total_weather += Decimal(str(p['weather_discount']))
        total_empty += Decimal(str(p['empty_slot_discount']))
        total_final += Decimal(str(p['final_price']))
        rain_mm = max(rain_mm, rain)

    normalized = dict(target)
    normalized.update(
        {
            'option_id': f'{facility_id}:{"+".join(str(s.id) for s in ordered_slots)}:{format(requested_hours, "f")}',
            'slot_ids': [int(s.id) for s in ordered_slots],
            'facility_id': int(slot.facility_id),
            'facility_name': slot.facility.name,
            'sport_type': slot.facility.sport_type,
            'is_indoor': bool(slot.facility.is_indoor),
            'start_at': bundle_start.isoformat(),
            'end_at': bundle_end.isoformat(),
            'duration_hours': float(requested_hours),
            'slot_version': max(int(s.slot_version) for s in ordered_slots),
            'reservation_hold_until': max(
                [s.reservation_hold_until for s in ordered_slots if s.reservation_hold_until is not None],
                default=None,
            ).isoformat()
            if any(s.reservation_hold_until is not None for s in ordered_slots)
            else None,
            'current_bookings': max(int(s.current_bookings) for s in ordered_slots),
            'max_bookings': min(int(s.max_bookings) for s in ordered_slots),
            'available_spots': min(max(0, int(s.max_bookings) - int(s.current_bookings)) for s in ordered_slots),
            'base_price': str(total_base.quantize(Decimal('0.01'))),
            'weather_discount': str(total_weather.quantize(Decimal('0.01'))),
            'empty_slot_discount': str(total_empty.quantize(Decimal('0.01'))),
            'final_price': str(total_final.quantize(Decimal('0.01'))),
            'rain_mm': float(rain_mm),
            'is_available': bool(
                all(
                    s.is_open
                    and s.current_bookings < s.max_bookings
                    and not (s.reservation_hold_until and s.reservation_hold_until > timezone.now())
                    for s in ordered_slots
                )
            ),
        }
    )
    return normalized


def _looks_like_exact_confirm(message):
    lowered = (message or '').lower()
    keywords = [
        'exact slot',
        'book this exact',
        'book exact',
        'confirm exact',
        'auto-book exact',
    ]
    return any(keyword in lowered for keyword in keywords)


def _build_payment_quote_payload(target, text='Slot is available. Complete payment to lock and confirm it.'):
    target = _canonicalize_target_for_quote(target)
    amount = str(target.get('final_price') or target.get('base_price') or '0')
    currency = str(target.get('currency') or 'USD')
    issued_at = timezone.now()
    expires_at = issued_at + timedelta(minutes=PAYMENT_WINDOW_MINUTES)

    preview_start = parse_datetime(str(target.get('start_at') or '')) if target.get('start_at') else None
    preview_end = parse_datetime(str(target.get('end_at') or '')) if target.get('end_at') else None
    if preview_start is not None and timezone.is_naive(preview_start):
        preview_start = timezone.make_aware(preview_start)
    if preview_end is not None and timezone.is_naive(preview_end):
        preview_end = timezone.make_aware(preview_end)

    preview_text = text
    if preview_start is not None and preview_end is not None:
        local_start = timezone.localtime(preview_start)
        local_end = timezone.localtime(preview_end)
        preview_text = (
            f'{text}\n'
            'Booking preview:\n'
            f"- Venue: {target.get('facility_name')}\n"
            f"- Date: {local_start.date().isoformat()}\n"
            f"- Time: {local_start.strftime('%H:%M')} - {local_end.strftime('%H:%M')}"
        )

    return {
        'type': 'payment_quote',
        'text': preview_text,
        'payment_quote': {
            'amount': amount,
            'currency': currency,
            'issued_at': issued_at.isoformat(),
            'expires_at': expires_at.isoformat(),
        },
        'booking_preview': {
            'facility_name': target.get('facility_name'),
            'start_at': target.get('start_at'),
            'end_at': target.get('end_at'),
            'option_id': target.get('option_id'),
        },
        'selected_option': target,
    }


def _create_confirmed_booking_from_target(target, user_uuid, booking_source=BookingSource.CHATBOT, chatbot_session_id=''):
    facility_id, slot_ids = _target_option_chunks(target)
    duration_hours = Decimal(str(target.get('duration_hours', 1) or 1))

    with transaction.atomic():
        slots = list(
            TimeSlot.objects.select_for_update().filter(id__in=slot_ids, facility_id=facility_id, is_open=True)
        )
        if len(slots) != len(slot_ids):
            raise TimeSlot.DoesNotExist

        slot_map = {str(slot.id): slot for slot in slots}
        ordered_slots = []
        for sid in slot_ids:
            slot = slot_map.get(str(sid))
            if slot is None:
                raise TimeSlot.DoesNotExist
            ordered_slots.append(slot)

        for i in range(1, len(ordered_slots)):
            if ordered_slots[i - 1].end_at != ordered_slots[i].start_at:
                raise ValueError('Requested duration is no longer available as consecutive slots.')

        slot_price = Decimal(str(target.get('final_price') or target.get('base_price') or '0'))
        per_slot_price = (slot_price / Decimal(len(ordered_slots))).quantize(Decimal('0.01'))
        bookings = []
        for idx, slot in enumerate(ordered_slots):
            already_booked = Booking.objects.filter(
                user_id=user_uuid,
                time_slot_id=slot.id,
            ).exclude(status=BookingStatus.CANCELLED).exists()
            if already_booked:
                raise ValueError('You already booked one of the selected slots.')

            slot_taken = Booking.objects.filter(time_slot_id=slot.id).exclude(status=BookingStatus.CANCELLED).exists()
            if slot_taken or slot.current_bookings >= slot.max_bookings:
                raise ValueError('One of the selected slots is no longer available.')

            slot.current_bookings += 1
            slot.reservation_hold_until = None
            slot.is_open = False
            slot.save(update_fields=['current_bookings', 'reservation_hold_until', 'is_open', 'availability_state', 'updated_at'])

            row_duration = Decimal((slot.end_at - slot.start_at).total_seconds() / 3600).quantize(Decimal('0.01'))
            row_price = per_slot_price
            if idx == len(ordered_slots) - 1:
                row_price = (slot_price - (per_slot_price * Decimal(len(ordered_slots) - 1))).quantize(Decimal('0.01'))

            booking = Booking.objects.create(
                user_id=user_uuid,
                facility_id=facility_id,
                time_slot=slot,
                start_at=slot.start_at,
                end_at=slot.end_at,
                duration_hours=row_duration,
                status=BookingStatus.CONFIRMED,
                payment_status=PaymentStatus.MOCK_PAID,
                base_price=row_price,
                weather_discount=Decimal('0.00'),
                empty_slot_discount=Decimal('0.00'),
                final_price=row_price,
                weather_rain_mm=float(target.get('rain_mm', 0.0)),
                booking_source=booking_source,
                chatbot_session_id=chatbot_session_id or '',
            )
            bookings.append((slot, booking))

    for slot, booking in bookings:
        _sync_to_supabase_async(slot=slot, booking=booking)
    return [booking for _, booking in bookings]


def _is_payment_status_query(message):
    lowered = message.lower()
    keywords = [
        'i paid',
        'payment done',
        'paid already',
        'payment status',
        'is payment confirmed',
        'did my payment go through',
    ]
    return any(keyword in lowered for keyword in keywords)


def _is_alternative_browse_query(message):
    lowered = (message or '').lower()
    keywords = [
        'show alternatives',
        'show other',
        'other slots',
        'another slot',
        'another time',
        'other time',
        'browse',
        'more options',
        'next slots',
    ]
    return any(keyword in lowered for keyword in keywords)


def _is_list_all_slots_query(message):
    lowered = (message or '').lower()
    triggers = [
        'available slots at',
        'slots at',
        'venue slots',
        'show slots',
        'list slots',
        'what time is available at',
    ]
    return any(token in lowered for token in triggers)


def _requested_slot_count(message):
    lowered = (message or '').lower()
    m = re.search(r'\b(\d{1,2})\s*slots?\b', lowered)
    if m:
        try:
            return max(1, int(m.group(1)))
        except Exception:
            return 1
    if any(token in lowered for token in ['multiple slots', 'several slots', 'many slots']):
        return 2
    return 1


def _reference_option_index_from_message(message, suggestion_count):
    lowered = (message or '').lower().strip()
    if not lowered or suggestion_count <= 0:
        return None

    if any(token in lowered for token in ['the last one', 'last one', 'last slot', 'last option']):
        return suggestion_count
    if any(token in lowered for token in ['the first one', 'first one', 'first slot', 'first option']):
        return 1

    m = re.search(r'\b(?:number|no\.?|option|slot)\s*(\d{1,3})\b', lowered)
    if m:
        idx = int(m.group(1))
        if 1 <= idx <= suggestion_count:
            return idx

    return None


def _chatbot_slots_cache_key(date_str, sport_type=None, is_indoor=None):
    sport_part = (sport_type or 'all').strip().lower()
    indoor_part = 'all' if is_indoor is None else ('indoor' if bool(is_indoor) else 'outdoor')
    revision = _chatbot_cache_revision()
    return f'chat:slots-by-venue:v2:{revision}:{date_str}:{sport_part}:{indoor_part}'


def _chatbot_display_venue_name(name):
    text = str(name or '').strip()
    if not text:
        return text

    # Keep canonical record name internally, but show a cleaner venue label in chatbot text.
    text = re.sub(r'\s*-\s*(pitch|court|table)\s*(#?\d+|[a-z])\s*$', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\s+(pitch|court|table)\s*(#?\d+|[a-z])\s*$', '', text, flags=re.IGNORECASE)
    return text.strip() or str(name or '').strip()


def _matched_venue_prefix(extracted):
    venue_name = str((extracted or {}).get('facility_name') or '').strip()
    if not venue_name:
        return ''
    return f"Matched venue: {_chatbot_display_venue_name(venue_name)}.\n"


def _chat_request_summary(extracted):
    data = extracted or {}
    venue = str(data.get('facility_name') or '').strip() or 'Any venue'
    date_value = str(data.get('date') or '').strip() or 'Any date'
    start_time = str(data.get('start_time') or '').strip() or 'Any time'
    end_time = str(data.get('end_time') or '').strip()
    sport_type = str(data.get('sport_type') or '').strip() or 'Any sport'

    if end_time:
        time_text = f'{start_time} to {end_time}'
    else:
        time_text = start_time

    return (
        'Request summary:\n'
        f'- Venue: {_chatbot_display_venue_name(venue)}\n'
        f'- Sport: {sport_type}\n'
        f'- Date: {date_value}\n'
        f'- Time: {time_text}'
    )


def _suggest_venue_names_from_hint(hint, limit=5):
    normalized_hint = _normalize_text(hint)
    if not normalized_hint:
        return []

    hint_compact = normalized_hint.replace(' ', '')
    hint_tokens = [token for token in normalized_hint.split() if len(token) >= 3]
    rows = _active_facility_rows_cached()

    scored = []
    for row in rows:
        name = str(row.get('name') or '').strip()
        if not name:
            continue
        normalized_name = _normalize_text(name)
        name_compact = normalized_name.replace(' ', '')

        token_hits = sum(1 for token in hint_tokens if token in normalized_name)
        compact_bonus = 2 if (hint_compact and (hint_compact in name_compact or name_compact in hint_compact)) else 0
        ratio = SequenceMatcher(None, normalized_hint, normalized_name).ratio()
        score = token_hits + compact_bonus + ratio
        scored.append((score, name))

    scored.sort(key=lambda item: (-item[0], item[1].lower()))
    names = []
    for _, name in scored:
        if name not in names:
            names.append(name)
        if len(names) >= limit:
            break
    return names


def _cached_available_slots_by_venue(date_str, sport_type=None, is_indoor=None):
    cache_key = _chatbot_slots_cache_key(date_str, sport_type=sport_type, is_indoor=is_indoor)
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    _, day_start, day_end = _date_bounds_for_query(date_str)
    if day_start is None or day_end is None:
        return {}

    now = timezone.now()
    qs = (
        TimeSlot.objects.select_related('facility')
        .filter(
            facility__is_active=True,
            start_at__gte=day_start,
            start_at__lt=day_end,
            is_open=True,
            current_bookings__lt=models.F('max_bookings'),
        )
        .order_by('start_at')
    )
    if sport_type:
        qs = qs.filter(facility__sport_type=sport_type)
    if is_indoor is not None:
        qs = qs.filter(facility__is_indoor=is_indoor)

    output = {}
    for slot in qs:
        # Ignore past starts for same-day queries.
        if slot.start_at < now:
            continue
        if slot.reservation_hold_until and slot.reservation_hold_until > now:
            continue

        rows = output.setdefault(
            slot.facility_id,
            {
                'facility': slot.facility,
                'slots': [],
            },
        )
        rows['slots'].append(
            {
                'id': slot.id,
                'start_at': slot.start_at,
                'end_at': slot.end_at,
                'current_bookings': int(slot.current_bookings),
                'max_bookings': int(slot.max_bookings),
                'slot_version': int(slot.slot_version),
                'reservation_hold_until': slot.reservation_hold_until,
            }
        )

    # Short TTL keeps cache fresh while still reducing repetitive DB scans in chatbot flows.
    cache.set(cache_key, output, timeout=45)
    return output


def _payment_status_payload(booking):
    if booking.payment_status == PaymentStatus.MOCK_PAID and booking.status == BookingStatus.CONFIRMED:
        return {
            'type': 'payment_confirmed',
            'booking_id': booking.id,
            'status': booking.status,
            'payment_status': booking.payment_status,
            'text': 'Payment confirmed. Your slot is fully booked and confirmed in the database.',
        }

    if booking.payment_status == PaymentStatus.MOCK_PENDING:
        return {
            'type': 'payment_pending',
            'booking_id': booking.id,
            'status': booking.status,
            'payment_status': booking.payment_status,
            'text': 'Your booking exists but payment is still pending. Complete payment to confirm the slot.',
        }

    return {
        'type': 'payment_status',
        'booking_id': booking.id,
        'status': booking.status,
        'payment_status': booking.payment_status,
        'text': 'Booking located. Please check booking history for latest status.',
    }


def _build_suggestions(extracted, limit=3):
    _ensure_rolling_slot_window_cached()
    sport_type = extracted.get('sport_type')
    is_indoor = extracted.get('is_indoor')
    facility_name = extracted.get('facility_name')
    date_str = extracted.get('date')
    start_time = extracted.get('start_time')
    end_time = extracted.get('end_time')
    duration_hours = extracted.get('duration_hours') or 1
    requested_duration_hours = Decimal(str(duration_hours))

    if not date_str or not start_time:
        return []

    requested_start = parse_datetime(f'{date_str}T{start_time}:00')
    if requested_start is None:
        return []
    if timezone.is_naive(requested_start):
        requested_start = timezone.make_aware(requested_start)

    requested_end = None
    if end_time:
        requested_end = parse_datetime(f'{date_str}T{end_time}:00')
        if requested_end is not None and timezone.is_naive(requested_end):
            requested_end = timezone.make_aware(requested_end)
    cached_by_venue = _cached_available_slots_by_venue(date_str, sport_type=sport_type, is_indoor=is_indoor)
    if not cached_by_venue:
        return []

    facility_entries = list(cached_by_venue.values())
    if facility_name:
        resolved = _resolve_active_facility_from_hint(facility_name, strict=True)
        if not resolved:
            resolved = _resolve_active_facility_from_hint(facility_name)
        if resolved:
            target_display = _chatbot_display_venue_name(resolved['name']).lower()
            grouped = []
            for entry in facility_entries:
                display = _chatbot_display_venue_name(entry['facility'].name).lower()
                if display == target_display:
                    grouped.append(entry)

            if grouped:
                facility_entries = grouped
            else:
                exact_entry = cached_by_venue.get(resolved['id'])
                if exact_entry is None:
                    return []
                facility_entries = [exact_entry]
        else:
            return []

    output = []
    rain_by_facility = {}

    # For requests longer than one hour, build consecutive-slot bundles first.
    try:
        required_minutes = int(round(float(requested_duration_hours) * 60))
    except Exception:
        required_minutes = 60

    if required_minutes > 60:
        bundled = []
        now_ts = timezone.now()
        for entry in facility_entries:
            facility = entry['facility']
            candidates = []
            for slot_row in entry['slots']:
                hold_until = slot_row.get('reservation_hold_until')
                if hold_until is not None and timezone.is_naive(hold_until):
                    hold_until = timezone.make_aware(hold_until)
                if hold_until is not None and hold_until > now_ts:
                    continue

                current = int(slot_row.get('current_bookings', 0))
                max_bookings = int(slot_row.get('max_bookings', 1))
                if current >= max_bookings:
                    continue

                start_at = slot_row.get('start_at')
                end_at = slot_row.get('end_at')
                if not start_at or not end_at:
                    continue
                if timezone.is_naive(start_at):
                    start_at = timezone.make_aware(start_at)
                if timezone.is_naive(end_at):
                    end_at = timezone.make_aware(end_at)

                if start_at.date() != requested_start.date():
                    continue
                if requested_end is not None and (start_at < requested_start or end_at > requested_end):
                    continue

                candidates.append(
                    {
                        'id': slot_row['id'],
                        'start_at': start_at,
                        'end_at': end_at,
                        'current_bookings': current,
                        'max_bookings': max_bookings,
                        'slot_version': int(slot_row.get('slot_version') or 1),
                        'hold_until': hold_until,
                    }
                )

            if not candidates:
                continue

            candidates.sort(key=lambda row: row['start_at'])
            by_start = {row['start_at']: row for row in candidates}
            for first in candidates:
                chain = [first]
                covered = int((first['end_at'] - first['start_at']).total_seconds() // 60)
                cursor = first['end_at']

                while covered < required_minutes:
                    nxt = by_start.get(cursor)
                    if nxt is None:
                        break
                    chain.append(nxt)
                    covered += int((nxt['end_at'] - nxt['start_at']).total_seconds() // 60)
                    cursor = nxt['end_at']

                if covered != required_minutes:
                    continue

                bundle_start = chain[0]['start_at']
                bundle_end = chain[-1]['end_at']
                if requested_end is not None and (bundle_start < requested_start or bundle_end > requested_end):
                    continue

                total_base = Decimal('0.00')
                total_weather = Decimal('0.00')
                total_empty = Decimal('0.00')
                total_final = Decimal('0.00')
                rain = 0.0
                for row in chain:
                    occupancy = row['current_bookings'] / row['max_bookings'] if row['max_bookings'] else 1.0
                    slot_rain = 0.0
                    if not facility.is_indoor:
                        slot_rain = rain_by_facility.get(facility.id, 0.0)
                        if facility.id not in rain_by_facility:
                            try:
                                slot_rain = _cached_rain_mm(facility.latitude, facility.longitude, date_str)
                            except Exception:
                                slot_rain = 0.0
                            rain_by_facility[facility.id] = slot_rain
                    rain = max(rain, slot_rain)
                    p = Booking.compute_dynamic_price(
                        base_price_per_hour=facility.base_price_per_hour,
                        duration_hours=Decimal('1.00'),
                        is_indoor=facility.is_indoor,
                        rain_mm=slot_rain,
                        occupancy_rate=occupancy,
                    )
                    total_base += Decimal(str(p['base_price']))
                    total_weather += Decimal(str(p['weather_discount']))
                    total_empty += Decimal(str(p['empty_slot_discount']))
                    total_final += Decimal(str(p['final_price']))

                slot_ids = [str(row['id']) for row in chain]
                bundled.append(
                    {
                        'option_id': f"{facility.id}:{'+'.join(slot_ids)}:{format(Decimal(required_minutes) / Decimal(60), 'f')}",
                        'slot_ids': [int(sid) for sid in slot_ids],
                        'facility_id': facility.id,
                        'facility_name': facility.name,
                        'sport_type': facility.sport_type,
                        'is_indoor': facility.is_indoor,
                        'start_at': bundle_start.isoformat(),
                        'end_at': bundle_end.isoformat(),
                        'duration_hours': round(required_minutes / 60, 2),
                        'requested_duration_hours': float(requested_duration_hours),
                        'rain_mm': rain,
                        'base_price': str(total_base.quantize(Decimal('0.01'))),
                        'weather_discount': str(total_weather.quantize(Decimal('0.01'))),
                        'empty_slot_discount': str(total_empty.quantize(Decimal('0.01'))),
                        'final_price': str(total_final.quantize(Decimal('0.01'))),
                        'currency': 'USD',
                        'current_bookings': max(row['current_bookings'] for row in chain),
                        'max_bookings': min(row['max_bookings'] for row in chain),
                        'available_spots': min(max(0, row['max_bookings'] - row['current_bookings']) for row in chain),
                        'is_available': all(row['current_bookings'] == 0 for row in chain),
                        'is_exact_match': bundle_start == requested_start,
                        'time_gap_minutes': abs(int((bundle_start - requested_start).total_seconds() // 60)),
                        'slot_version': max(int(row['slot_version']) for row in chain),
                        'reservation_hold_until': None,
                    }
                )

        if bundled:
            exact_matches = [item for item in bundled if item.get('is_exact_match')]
            if exact_matches:
                exact_matches.sort(key=lambda item: (Decimal(item['final_price']), item['start_at']))
                others = [item for item in bundled if not item.get('is_exact_match')]
                others.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
                ranked = exact_matches + others
            else:
                bundled.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
                ranked = bundled
            for item in ranked:
                item.pop('time_gap_minutes', None)
            return ranked[:limit]

    for entry in facility_entries:
        facility = entry['facility']
        for slot_row in entry['slots']:
            hold_until = slot_row.get('reservation_hold_until')
            if hold_until is not None and timezone.is_naive(hold_until):
                hold_until = timezone.make_aware(hold_until)
            if hold_until is not None and hold_until > timezone.now():
                continue

            current = int(slot_row.get('current_bookings', 0))
            max_bookings = int(slot_row.get('max_bookings', 1))
            if current >= max_bookings:
                continue

            start_at = slot_row.get('start_at')
            end_at = slot_row.get('end_at')
            if not start_at or not end_at:
                continue

            if timezone.is_naive(start_at):
                start_at = timezone.make_aware(start_at)
            if timezone.is_naive(end_at):
                end_at = timezone.make_aware(end_at)

            if start_at.date() != requested_start.date():
                continue

            if requested_end is not None:
                if start_at < requested_start or end_at > requested_end:
                    continue

            slot_hours = Decimal((end_at - start_at).total_seconds() / 3600).quantize(Decimal('0.01'))
            # In explicit range mode, return all matching slots inside the requested window.
            if requested_end is None and slot_hours < requested_duration_hours:
                continue

            occupancy = current / max_bookings if max_bookings else 1.0
            rain = 0.0
            if not facility.is_indoor:
                rain = rain_by_facility.get(facility.id, 0.0)
                if facility.id not in rain_by_facility:
                    try:
                        rain = _cached_rain_mm(facility.latitude, facility.longitude, date_str)
                    except Exception:
                        rain = 0.0
                    rain_by_facility[facility.id] = rain
            price = Booking.compute_dynamic_price(
                base_price_per_hour=facility.base_price_per_hour,
                duration_hours=slot_hours,
                is_indoor=facility.is_indoor,
                rain_mm=rain,
                occupancy_rate=occupancy,
            )

            slot_hours_str = format(slot_hours, 'f')

            output.append(
                {
                    'option_id': f"{facility.id}:{slot_row['id']}:{slot_hours_str}",
                    'facility_id': facility.id,
                    'facility_name': facility.name,
                    'sport_type': facility.sport_type,
                    'is_indoor': facility.is_indoor,
                    'start_at': start_at.isoformat(),
                    'end_at': end_at.isoformat(),
                    'duration_hours': float(slot_hours),
                    'requested_duration_hours': float(requested_duration_hours),
                    'rain_mm': rain,
                    'base_price': str(price['base_price']),
                    'weather_discount': str(price['weather_discount']),
                    'empty_slot_discount': str(price['empty_slot_discount']),
                    'final_price': str(price['final_price']),
                    'currency': 'USD',
                    'current_bookings': current,
                    'max_bookings': max_bookings,
                    'available_spots': max(0, max_bookings - current),
                    'is_available': current == 0,
                    'is_exact_match': start_at == requested_start,
                    'time_gap_minutes': abs(int((start_at - requested_start).total_seconds() // 60)),
                    'slot_version': int(slot_row.get('slot_version') or 1),
                    'reservation_hold_until': hold_until.isoformat() if hold_until else None,
                }
            )

    exact_matches = [item for item in output if item.get('is_exact_match')]
    if exact_matches:
        exact_matches.sort(key=lambda item: (Decimal(item['final_price']), item['start_at']))
        other_slots = [item for item in output if not item.get('is_exact_match')]
        other_slots.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
        ranked = exact_matches + other_slots
    else:
        later_slots = [item for item in output if parse_datetime(item.get('start_at')) and parse_datetime(item.get('start_at')) >= requested_start]
        if later_slots:
            later_slots.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
            ranked = later_slots
        else:
            output.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
            ranked = output

    for item in ranked:
        item.pop('time_gap_minutes', None)

    return ranked[:limit]


def _range_mode_prefix(extracted):
    start_time = str((extracted or {}).get('start_time') or '').strip()
    end_time = str((extracted or {}).get('end_time') or '').strip()
    date_value = str((extracted or {}).get('date') or '').strip()
    if not (start_time and end_time):
        return ''
    date_suffix = f' on {date_value}' if date_value else ''
    return f'Time range mode: showing slots from {start_time} to {end_time}{date_suffix}.\n'


def _nearest_suggestions(extracted, limit=3, max_day_offset=3):
    sport_type = extracted.get('sport_type')
    date_str = extracted.get('date')
    start_time = extracted.get('start_time')
    if not sport_type or not date_str or not start_time:
        return []

    requested_start = parse_datetime(f'{date_str}T{start_time}:00')
    if requested_start is None:
        return []
    if timezone.is_naive(requested_start):
        requested_start = timezone.make_aware(requested_start)

    merged = []
    seen_option_ids = set()
    for offset in range(0, max_day_offset + 1):
        probe_date = (requested_start + timedelta(days=offset)).date().isoformat()
        probe = dict(extracted)
        probe['date'] = probe_date
        day_suggestions = _build_suggestions(probe, limit=limit * 3)
        for item in day_suggestions:
            option_id = str(item.get('option_id') or '').strip()
            if not option_id or option_id in seen_option_ids:
                continue
            start_at = parse_datetime(item.get('start_at'))
            if start_at is None:
                continue
            if timezone.is_naive(start_at):
                start_at = timezone.make_aware(start_at)
            row = dict(item)
            row['time_gap_minutes'] = abs(int((start_at - requested_start).total_seconds() // 60))
            row['is_exact_match'] = row['time_gap_minutes'] == 0
            merged.append(row)
            seen_option_ids.add(option_id)

    merged.sort(key=lambda item: (item.get('time_gap_minutes', 10**9), Decimal(item['final_price']), item['start_at']))
    for item in merged:
        item.pop('time_gap_minutes', None)
    return merged[:limit]


def _extracted_from_suggestion(target):
    option_id = str(target.get('option_id') or '').strip()
    chunks = option_id.split(':') if option_id else []
    facility_id = chunks[0] if len(chunks) >= 1 else None

    sport_type = target.get('sport_type')
    is_indoor = target.get('is_indoor')
    if (sport_type is None or is_indoor is None) and facility_id:
        try:
            facility = Facility.objects.get(id=facility_id, is_active=True)
            if sport_type is None:
                sport_type = facility.sport_type
            if is_indoor is None:
                is_indoor = facility.is_indoor
        except Facility.DoesNotExist:
            pass

    start_at = parse_datetime(target.get('start_at')) if target.get('start_at') else None
    if start_at is not None and timezone.is_naive(start_at):
        start_at = timezone.make_aware(start_at)

    duration_hours = target.get('duration_hours') or 1
    if start_at is None:
        date_value = timezone.localdate().isoformat()
        start_value = '18:00'
    else:
        localized = timezone.localtime(start_at)
        date_value = localized.date().isoformat()
        start_value = localized.strftime('%H:%M')

    return {
        'intent': 'search',
        'sport_type': sport_type,
        'is_indoor': is_indoor,
        'date': date_value,
        'start_time': start_value,
        'duration_hours': float(duration_hours),
        'reference_option_index': None,
    }


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def chat_endpoint(request):
    try:
        message = (request.data.get('message') or '').strip()
        user_id = _uuid_from_user(request.user)
        _release_expired_pending_bookings(user_uuid=user_id)
        selected_option_id = str(request.data.get('selected_option_id') or '').strip()
        prior_suggestions = request.data.get('suggestions') or []
        if not isinstance(prior_suggestions, list):
            prior_suggestions = []
        reference_option_index = _reference_option_index_from_message(message, len(prior_suggestions))
        message_lower = message.lower()
        browse_alternatives_requested = _is_alternative_browse_query(message)
        list_all_slots_requested = _is_list_all_slots_query(message)
        requested_slots = _requested_slot_count(message)
        keyword_intent = _keyword_intent_hint(message)
        booking_source_raw = (request.data.get('booking_source') or BookingSource.CHATBOT).strip().lower()
        chatbot_session_id = (request.data.get('chatbot_session_id') or '').strip()
        booking_source = BookingSource.CHATBOT if booking_source_raw == BookingSource.CHATBOT else BookingSource.MANUAL
        chat_context = _load_chat_context(user_id, chatbot_session_id)

        if not message:
            return Response({'error': 'message is required'}, status=status.HTTP_400_BAD_REQUEST)

        if _is_payment_status_query(message):
            booking_qs = Booking.objects.filter(user_id=user_id).order_by('-created_at')
            if chatbot_session_id:
                booking_qs = booking_qs.filter(chatbot_session_id=chatbot_session_id)
            booking = booking_qs.first()
            if booking is None:
                return Response(
                    {
                        'type': 'payment_status',
                        'text': 'No booking found yet. Ask me to find a slot first.',
                    }
                )
            return Response(_payment_status_payload(booking))

        # Route normal questions to FAQ/help mode before booking extraction.
        if keyword_intent == 'faq':
            faq_payload = _faq_answer(message)
            if faq_payload is not None:
                return Response(faq_payload)

        if message_lower in ['confirm', 'book this', 'book it', 'book this slot', 'confirm booking'] and prior_suggestions:
            target = None
            if selected_option_id:
                target = next(
                    (
                        item
                        for item in prior_suggestions
                        if str(item.get('option_id') or '').strip() == selected_option_id
                    ),
                    None,
                )
            elif _looks_like_exact_confirm(message):
                target = next((item for item in prior_suggestions if bool(item.get('is_exact_match'))), None)
            if target is None:
                target = prior_suggestions[0]

            target = _canonicalize_target_for_quote(target)

            if not _is_target_currently_available(target):
                extracted_from_target = _extracted_from_suggestion(target)
                alternatives = _nearest_suggestions(extracted_from_target)
                if alternatives:
                    return Response(
                        {
                            'type': 'suggestions',
                            'text': 'That slot was just taken. Here are the closest available alternatives.',
                            'extracted': extracted_from_target,
                            'exact_match_found': any(bool(item.get('is_exact_match')) for item in alternatives),
                            'suggestions': alternatives,
                        }
                    )
                return Response({'error': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)

            if booking_source == BookingSource.MANUAL:
                try:
                    booking = _create_pending_booking(
                        target,
                        user_uuid=user_id,
                        booking_source=booking_source,
                        chatbot_session_id=chatbot_session_id,
                    )
                except TimeSlot.DoesNotExist:
                    return Response({'error': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)
                except ValueError as ex:
                    return Response({'error': str(ex)}, status=status.HTTP_409_CONFLICT)

                return Response(
                    {
                        'type': 'pending_booking_created',
                        'text': f'Pending booking created. Complete payment within {PAYMENT_WINDOW_MINUTES} minutes.',
                        'booking_id': booking.id,
                        'status': booking.status,
                        'payment_status': booking.payment_status,
                        'final_price': str(booking.final_price),
                        'currency': 'USD',
                        'payment_expires_at': _payment_deadline_for_booking(booking).isoformat(),
                        'booking_source': booking.booking_source,
                        'chatbot_session_id': booking.chatbot_session_id,
                    },
                    status=status.HTTP_201_CREATED,
                )

            return Response(_build_payment_quote_payload(target, text='Slot is free now. Simulate payment to lock and confirm it.'))

        fallback_extracted = _fallback_extract_from_message(message)
        has_local_search_data = (
            fallback_extracted.get('intent') == 'search'
            and bool(fallback_extracted.get('sport_type'))
            and bool(fallback_extracted.get('date'))
            and bool(fallback_extracted.get('start_time'))
        )
        if has_local_search_data:
            extracted = fallback_extracted
        else:
            extracted = _call_ai_extractor(message)
            extracted = _merge_extracted(extracted, fallback_extracted)

        extracted = _merge_with_chat_context(extracted, chat_context)

        if reference_option_index is not None and any(token in message_lower for token in ['book', 'confirm', 'reserve', 'last one', 'first one', 'number', 'option', 'slot']):
            extracted['intent'] = 'confirm'
            extracted['reference_option_index'] = reference_option_index

        # Time/date-only follow-ups should continue the previous booking context.
        has_followup_time_data = bool(
            fallback_extracted.get('date') or fallback_extracted.get('start_time') or fallback_extracted.get('duration_hours')
        )
        has_followup_venue_or_sport = bool(fallback_extracted.get('facility_name') or fallback_extracted.get('sport_type'))
        if (
            extracted.get('intent') in [None, '', 'unknown']
            and has_followup_time_data
            and not has_followup_venue_or_sport
            and (chat_context.get('facility_name') or chat_context.get('sport_type'))
        ):
            extracted['intent'] = 'search'
            extracted['facility_name'] = extracted.get('facility_name') or chat_context.get('facility_name')
            extracted['sport_type'] = extracted.get('sport_type') or chat_context.get('sport_type')

        # Avoid carrying previous venue into a new standalone booking prompt.
        continuation_tokens = ['same place', 'same venue', 'same court', 'same table', 'same time', 'same hour', 'another']
        looks_like_new_booking = any(token in message_lower for token in ['book', 'reserve', 'available', 'find slot', 'show slots'])
        if looks_like_new_booking and not any(token in message_lower for token in continuation_tokens):
            explicit_facility_from_message = _find_facility_name_in_message(message)
            if not explicit_facility_from_message:
                extracted['facility_name'] = None

        # Preserve explicit user date/time/venue from local parser when AI extraction conflicts.
        if fallback_extracted.get('intent') == 'search':
            for key in ['facility_name', 'sport_type', 'date', 'start_time', 'end_time', 'duration_hours']:
                value = fallback_extracted.get(key)
                if value not in [None, '', 'unknown']:
                    extracted[key] = value

        # If user explicitly provides a fresh start+duration (<=1h) without end_time, clear stale end_time from context.
        if (
            fallback_extracted.get('start_time')
            and not fallback_extracted.get('end_time')
            and float(fallback_extracted.get('duration_hours') or 1) <= 1.0
        ):
            extracted['end_time'] = None

        resolved_facility = _resolve_active_facility_from_hint(extracted.get('facility_name'))
        if resolved_facility:
            # Venue-specific requests must stay anchored to the canonical venue.
            extracted['facility_name'] = resolved_facility['name']
            extracted['sport_type'] = resolved_facility['sport_type']
            extracted['is_indoor'] = None

        hinted_venue = _extract_facility_hint_from_message(message)
        if hinted_venue and not resolved_facility and (
            keyword_intent == 'search' or extracted.get('intent') == 'search' or list_all_slots_requested
        ) and extracted.get('intent') != 'confirm':
            venue_suggestions = _suggest_venue_names_from_hint(hinted_venue, limit=5)
            venue_text = (
                'Did you mean:\n- ' + '\n- '.join(_chatbot_display_venue_name(name) for name in venue_suggestions)
                if venue_suggestions
                else 'Try typing the exact venue name shown in the app.'
            )
            return Response(
                {
                    'type': 'clarify',
                    'text': (
                        f'I could not match venue "{hinted_venue}".\n'
                        f'{venue_text}'
                    ),
                }
            )

        if extracted.get('intent') in [None, '', 'unknown'] and keyword_intent == 'search':
            extracted['intent'] = 'search'

        if prior_suggestions and not extracted.get('facility_name') and any(token in message_lower for token in ['same place', 'same venue', 'same court', 'same table', 'another']):
            extracted['facility_name'] = prior_suggestions[0].get('facility_name')

        if any(token in message_lower for token in ['same place', 'same venue', 'same court', 'same table']):
            if chat_context.get('facility_name'):
                extracted['facility_name'] = chat_context.get('facility_name')
        if any(token in message_lower for token in ['same time', 'same hour']):
            if chat_context.get('start_time'):
                extracted['start_time'] = chat_context.get('start_time')
            if chat_context.get('duration_hours'):
                extracted['duration_hours'] = chat_context.get('duration_hours')

        if extracted.get('intent') in [None, '', 'unknown']:
            followup_tokens = ['how about', 'available', 'another', 'same place', 'same time', 'same day', 'other place', 'nearby', 'next', 'this']
            if any(token in message_lower for token in followup_tokens):
                extracted['intent'] = 'search'

        if extracted.get('intent') == 'search':
            if not extracted.get('date'):
                extracted['date'] = chat_context.get('date') or timezone.localdate().isoformat()
            if not extracted.get('start_time'):
                extracted['start_time'] = '00:00' if list_all_slots_requested else (chat_context.get('start_time') or '18:00')
            if not extracted.get('duration_hours'):
                extracted['duration_hours'] = chat_context.get('duration_hours') or 1.0
            if not extracted.get('sport_type'):
                extracted['sport_type'] = chat_context.get('sport_type')
            extracted['is_indoor'] = None

            # Multi-hour request without explicit end time should search as a range.
            if extracted.get('start_time') and extracted.get('duration_hours') and not extracted.get('end_time'):
                try:
                    duration_hours = float(extracted.get('duration_hours') or 0)
                    if duration_hours > 1:
                        start_h, start_m = [int(x) for x in str(extracted['start_time']).split(':')]
                        start_total = start_h * 60 + start_m
                        end_total = start_total + int(round(duration_hours * 60))
                        if end_total <= 24 * 60:
                            extracted['end_time'] = f'{end_total // 60:02d}:{end_total % 60:02d}'
                except Exception:
                    pass

            # For multi-slot intent, force clear start/end guidance if missing end_time.
            if requested_slots > 1 and not extracted.get('end_time'):
                return Response(
                    {
                        'type': 'clarify',
                        'text': (
                            f'I can help with {requested_slots} slots. Please provide a time range using start and end time. '
                            'Example: from 6pm to 8pm tomorrow at your venue.'
                        ),
                    }
                )

        intent = extracted.get('intent', 'unknown')
        auto_book_requested = bool(re.search(r'\b(book|reserve|confirm now|auto book)\b', message_lower))

        if intent == 'search':
            _save_chat_context(user_id, chatbot_session_id, extracted)
            range_prefix = _range_mode_prefix(extracted)
            summary_prefix = _chat_request_summary(extracted) + '\n'
            suggestion_limit = 50 if list_all_slots_requested else (8 if browse_alternatives_requested else 5)
            suggestions = _build_suggestions(extracted, limit=suggestion_limit)
            if not suggestions:
                if extracted.get('facility_name') and list_all_slots_requested:
                    # Relaxed same-venue fallback: show all available slots for the day.
                    relaxed = dict(extracted)
                    relaxed['start_time'] = '00:00'
                    relaxed['end_time'] = None
                    relaxed['duration_hours'] = 1.0
                    relaxed_suggestions = _build_suggestions(relaxed, limit=50)
                    if relaxed_suggestions:
                        return Response(
                            {
                                'type': 'suggestions',
                                'text': summary_prefix
                                + _matched_venue_prefix(extracted)
                                + 'No slots matched your exact requested time. Here are all available slots for that venue on the day.',
                                'extracted': relaxed,
                                'exact_match_found': any(bool(item.get('is_exact_match')) for item in relaxed_suggestions),
                                'suggestions': relaxed_suggestions,
                            }
                        )
                    return Response(
                        {
                            'type': 'no_slots',
                            'text': summary_prefix
                            + _matched_venue_prefix(extracted)
                            + range_prefix
                            + 'No free slots were found for that venue on the selected day. Try another date or time.',
                            'extracted': extracted,
                        }
                    )
                alternatives = _nearest_suggestions(extracted)
                if alternatives:
                    return Response(
                        {
                            'type': 'suggestions',
                            'text': summary_prefix + _matched_venue_prefix(extracted) + range_prefix + 'Requested slot is unavailable. Here are the closest available slots.',
                            'extracted': extracted,
                            'exact_match_found': any(bool(item.get('is_exact_match')) for item in alternatives),
                            'suggestions': alternatives,
                        }
                    )
                return Response(
                    {
                        'type': 'no_slots',
                        'text': summary_prefix + _matched_venue_prefix(extracted) + range_prefix + 'No free slots were found for that day. Try another date or sport.',
                        'extracted': extracted,
                    }
                )

            exact_match_found = any(bool(item.get('is_exact_match')) for item in suggestions)

            if auto_book_requested and exact_match_found:
                top_choice = suggestions[0]
                if top_choice.get('is_available'):
                    return Response(_build_payment_quote_payload(top_choice, text='Exact slot found and free. Simulate payment now to lock it.'))

            if extracted.get('facility_name') and exact_match_found:
                exact_slots = [item for item in suggestions if bool(item.get('is_exact_match'))]

                if browse_alternatives_requested:
                    non_exact_slots = [item for item in suggestions if not bool(item.get('is_exact_match'))]
                    if non_exact_slots:
                        return Response(
                            {
                                'type': 'suggestions',
                                'text': summary_prefix
                                + _matched_venue_prefix(extracted)
                                + range_prefix
                                + 'Here are alternative times for the same venue. The exact requested slot is available if you want to book it directly.',
                                'extracted': extracted,
                                'exact_match_found': True,
                                'exact_slot': exact_slots[0] if exact_slots else None,
                                'exact_only_mode': False,
                                'suggestions': non_exact_slots,
                            }
                        )

                    return Response(
                        {
                            'type': 'suggestions',
                            'text': summary_prefix
                            + _matched_venue_prefix(extracted)
                            + range_prefix
                            + 'Your exact requested slot is available, and there are no nearby alternatives right now.',
                            'extracted': extracted,
                            'exact_match_found': True,
                            'exact_slot': exact_slots[0] if exact_slots else None,
                            'exact_only_mode': True,
                            'suggestions': exact_slots[:1],
                        }
                    )

                return Response(
                    {
                        'type': 'suggestions',
                        'text': summary_prefix
                        + _matched_venue_prefix(extracted)
                        + range_prefix
                        + 'Exact slot found for your selected venue and time. Say "book this exact slot" to proceed, or "show alternatives" to browse other times.',
                        'extracted': extracted,
                        'exact_match_found': True,
                        'exact_slot': exact_slots[0] if exact_slots else None,
                        'exact_only_mode': True,
                        'suggestions': exact_slots[:1],
                    }
                )

            venue_names = []
            if not extracted.get('facility_name'):
                for item in suggestions:
                    name = str(item.get('facility_name') or '').strip()
                    if name and name not in venue_names:
                        venue_names.append(name)
                venue_names = venue_names[:3]
            venue_hint = (
                f" Available venues: {', '.join(venue_names)}."
                if venue_names and not extracted.get('facility_name')
                else ''
            )

            return Response(
                {
                    'type': 'suggestions',
                    'text': summary_prefix
                    + _matched_venue_prefix(extracted)
                    + range_prefix
                    + (
                        'Exact slot found. Choose one: auto-book this exact slot now, or browse slots below and book manually.'
                        if exact_match_found
                        else f'Exact time is unavailable. Here are other free slots on that day.{venue_hint} Tap Book this to continue.'
                    ),
                    'extracted': extracted,
                    'exact_match_found': exact_match_found,
                    'exact_slot': next((item for item in suggestions if item.get('is_exact_match')), None),
                    'action_choices': [
                        {'id': 'auto_book_exact', 'label': 'Auto-book exact slot'},
                        {'id': 'manual_pick', 'label': 'Browse slots manually'},
                    ] if exact_match_found else [],
                    'suggestions': suggestions,
                }
            )

        if intent == 'confirm' or message.lower() == 'confirm':
            target = None
            if selected_option_id:
                target = next(
                    (
                        item
                        for item in prior_suggestions
                        if str(item.get('option_id') or '').strip() == selected_option_id
                    ),
                    None,
                )
            elif extracted.get('reference_option_index') is not None:
                try:
                    raw_idx = int(extracted['reference_option_index'])
                    if raw_idx == -1:
                        idx = len(prior_suggestions) - 1
                    else:
                        idx = raw_idx - 1
                except (TypeError, ValueError):
                    idx = -1
                if 0 <= idx < len(prior_suggestions):
                    target = prior_suggestions[idx]
            elif _looks_like_exact_confirm(message):
                target = next((item for item in prior_suggestions if bool(item.get('is_exact_match'))), None)
            elif prior_suggestions:
                target = prior_suggestions[0]

            if not target:
                return Response({'error': 'No selected option found.'}, status=status.HTTP_400_BAD_REQUEST)

            target = _canonicalize_target_for_quote(target)

            if not _is_target_currently_available(target):
                extracted_from_target = _extracted_from_suggestion(target)
                alternatives = _nearest_suggestions(extracted_from_target)
                if alternatives:
                    return Response(
                        {
                            'type': 'suggestions',
                            'text': 'That slot is no longer available. Here are the closest alternatives.',
                            'extracted': extracted_from_target,
                            'exact_match_found': any(bool(item.get('is_exact_match')) for item in alternatives),
                            'suggestions': alternatives,
                        }
                    )
                return Response({'error': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)

            if booking_source == BookingSource.MANUAL:
                try:
                    booking = _create_pending_booking(
                        target,
                        user_uuid=user_id,
                        booking_source=booking_source,
                        chatbot_session_id=chatbot_session_id,
                    )
                except TimeSlot.DoesNotExist:
                    return Response({'error': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)
                except ValueError as ex:
                    return Response({'error': str(ex)}, status=status.HTTP_409_CONFLICT)

                return Response(
                    {
                        'type': 'pending_booking_created',
                        'text': f'Pending booking created. Complete payment within {PAYMENT_WINDOW_MINUTES} minutes.',
                        'booking_id': booking.id,
                        'status': booking.status,
                        'payment_status': booking.payment_status,
                        'final_price': str(booking.final_price),
                        'currency': 'USD',
                        'payment_expires_at': _payment_deadline_for_booking(booking).isoformat(),
                        'booking_source': booking.booking_source,
                        'chatbot_session_id': booking.chatbot_session_id,
                    },
                    status=status.HTTP_201_CREATED,
                )

            return Response(_build_payment_quote_payload(target, text='Slot is available. Simulate payment to confirm booking.'))

        return Response(
            {
                'type': 'clarify',
                'text': 'Please provide sport, date, start time, and duration. Example: book outdoor football tomorrow 5pm for 2 hours.',
            }
        )
    except Exception:
        return Response(
            {
                'error': 'AI booking is temporarily unavailable. Please try again.',
                'type': 'chat_error',
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mock_payment_endpoint(request):
    user_uuid = _uuid_from_user(request.user)
    _release_expired_pending_bookings(user_uuid=user_uuid)
    payment_channel = (request.data.get('payment_channel') or '').strip().lower()
    payment_provider = (request.data.get('payment_provider') or '').strip()
    coupon_code = (request.data.get('coupon_code') or '').strip().upper()
    chat_option = request.data.get('chat_option')

    if isinstance(chat_option, dict) and chat_option:
        chatbot_session_id = request.data.get('chatbot_session_id')
        if chatbot_session_id is not None:
            chatbot_session_id = str(chatbot_session_id).strip() or None
        booking_source = str(request.data.get('booking_source') or Booking.SOURCE_CHATBOT).strip() or Booking.SOURCE_CHATBOT

        payment_quote = request.data.get('payment_quote') if isinstance(request.data.get('payment_quote'), dict) else {}
        submitted_amount_raw = request.data.get('amount')

        try:
            expected_quote_amount = Decimal(str(chat_option.get('final_price') or chat_option.get('base_price') or '0')).quantize(Decimal('0.01'))
        except Exception:
            return Response({'error': 'Invalid chat quote amount.'}, status=status.HTTP_400_BAD_REQUEST)

        # Guard against stale/wrong option payload by enforcing slot identity and quoted time consistency.
        try:
            facility_id, slot_ids = _target_option_chunks(chat_option)
        except ValueError:
            return Response({'error': 'Invalid chat option selected.'}, status=status.HTTP_400_BAD_REQUEST)

        slots = list(TimeSlot.objects.filter(id__in=slot_ids, facility_id=facility_id).order_by('start_at'))
        if len(slots) != len(slot_ids):
            return Response({'error': 'Selected slot no longer exists.'}, status=status.HTTP_404_NOT_FOUND)

        slot_map = {str(slot.id): slot for slot in slots}
        ordered_slots = []
        for sid in slot_ids:
            slot = slot_map.get(str(sid))
            if slot is None:
                return Response({'error': 'Selected slot no longer exists.'}, status=status.HTTP_404_NOT_FOUND)
            ordered_slots.append(slot)

        for i in range(1, len(ordered_slots)):
            if ordered_slots[i - 1].end_at != ordered_slots[i].start_at:
                return Response({'error': 'Selected duration is no longer available. Please refresh and retry payment.'}, status=status.HTTP_409_CONFLICT)

        slot = ordered_slots[0]
        slot_end = ordered_slots[-1].end_at

        quoted_start_raw = chat_option.get('start_at')
        quoted_end_raw = chat_option.get('end_at')
        if quoted_start_raw:
            quoted_start = parse_datetime(str(quoted_start_raw))
            if quoted_start is None:
                return Response({'error': 'Invalid selected slot start time.'}, status=status.HTTP_400_BAD_REQUEST)
            if timezone.is_naive(quoted_start):
                quoted_start = timezone.make_aware(quoted_start)
            if abs((slot.start_at - quoted_start).total_seconds()) > 60:
                return Response({'error': 'Selected slot time changed. Please refresh and retry payment.'}, status=status.HTTP_409_CONFLICT)

        if quoted_end_raw:
            quoted_end = parse_datetime(str(quoted_end_raw))
            if quoted_end is None:
                return Response({'error': 'Invalid selected slot end time.'}, status=status.HTTP_400_BAD_REQUEST)
            if timezone.is_naive(quoted_end):
                quoted_end = timezone.make_aware(quoted_end)
            if abs((slot_end - quoted_end).total_seconds()) > 60:
                return Response({'error': 'Selected slot time changed. Please refresh and retry payment.'}, status=status.HTTP_409_CONFLICT)

        if payment_quote:
            quote_amount_raw = payment_quote.get('amount')
            if quote_amount_raw in (None, ''):
                return Response({'error': 'Payment quote amount is required.'}, status=status.HTTP_400_BAD_REQUEST)
            try:
                quote_amount = Decimal(str(quote_amount_raw)).quantize(Decimal('0.01'))
            except Exception:
                return Response({'error': 'Invalid payment quote amount.'}, status=status.HTTP_400_BAD_REQUEST)
            if quote_amount != expected_quote_amount:
                return Response({'error': 'Quote amount mismatch. Please request the slot again.'}, status=status.HTTP_400_BAD_REQUEST)

            expires_at_raw = payment_quote.get('expires_at')
            if expires_at_raw in (None, ''):
                return Response({'error': 'Payment quote expiry is required.'}, status=status.HTTP_400_BAD_REQUEST)
            quote_expires_at = parse_datetime(str(expires_at_raw))
            if quote_expires_at is None:
                return Response({'error': 'Invalid payment quote expiry.'}, status=status.HTTP_400_BAD_REQUEST)
            if timezone.is_naive(quote_expires_at):
                quote_expires_at = timezone.make_aware(quote_expires_at, dt_timezone.utc)
            if quote_expires_at <= timezone.now():
                return Response(
                    {
                        'error': f'Payment window expired ({PAYMENT_WINDOW_MINUTES} minutes). Please request quote again.',
                        'type': 'payment_window_expired',
                    },
                    status=status.HTTP_409_CONFLICT,
                )

        coupon = None
        discount_ratio = Decimal('0.00')
        if coupon_code:
            now = timezone.now()
            coupon = Coupon.objects.filter(
                code=coupon_code,
                is_active=True,
                archived_at__isnull=True,
                starts_at__lte=now,
                ends_at__gte=now,
            ).first()
            if coupon is None:
                return Response({'error': 'Invalid or expired coupon code.'}, status=status.HTTP_400_BAD_REQUEST)
            discount_ratio = (Decimal(coupon.discount_percent) / Decimal('100')).quantize(Decimal('0.0001'))

        expected_payable_amount = (expected_quote_amount * (Decimal('1.00') - discount_ratio)).quantize(Decimal('0.01'))
        if expected_payable_amount < Decimal('0.00'):
            expected_payable_amount = Decimal('0.00')

        if submitted_amount_raw not in (None, ''):
            try:
                submitted_amount = Decimal(str(submitted_amount_raw)).quantize(Decimal('0.01'))
            except Exception:
                return Response({'error': 'Invalid submitted amount.'}, status=status.HTTP_400_BAD_REQUEST)
            if submitted_amount != expected_payable_amount:
                return Response({'error': 'Payment amount mismatch. Please refresh quote and try again.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            created_bookings = _create_confirmed_booking_from_target(
                chat_option,
                user_uuid=user_uuid,
                booking_source=booking_source,
                chatbot_session_id=chatbot_session_id,
            )
        except TimeSlot.DoesNotExist:
            extracted_from_target = _extracted_from_suggestion(chat_option)
            alternatives = _nearest_suggestions(extracted_from_target)
            if alternatives:
                return Response(
                    {
                        'type': 'suggestions',
                        'text': 'That slot is no longer available. Here are close alternatives you can pay for now.',
                        'extracted': extracted_from_target,
                        'exact_match_found': any(bool(item.get('is_exact_match')) for item in alternatives),
                        'suggestions': alternatives,
                    },
                    status=status.HTTP_409_CONFLICT,
                )
            return Response({'error': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)
        except ValueError as ex:
            extracted_from_target = _extracted_from_suggestion(chat_option)
            alternatives = _nearest_suggestions(extracted_from_target)
            if alternatives:
                return Response(
                    {
                        'type': 'suggestions',
                        'text': f'{str(ex)} Here are close alternatives you can pay for now.',
                        'extracted': extracted_from_target,
                        'exact_match_found': any(bool(item.get('is_exact_match')) for item in alternatives),
                        'suggestions': alternatives,
                    },
                    status=status.HTTP_409_CONFLICT,
                )
            return Response({'error': str(ex)}, status=status.HTTP_409_CONFLICT)

        total_discount = Decimal('0.00')
        final_total = Decimal('0.00')
        for booking in created_bookings:
            if coupon is not None:
                row_discount = (Decimal(booking.final_price) * discount_ratio).quantize(Decimal('0.01'))
                discounted_price = (Decimal(booking.final_price) - row_discount).quantize(Decimal('0.01'))
                if discounted_price < Decimal('0.00'):
                    discounted_price = Decimal('0.00')
                booking.final_price = discounted_price
                booking.coupon_code = coupon.code
                booking.coupon_discount = row_discount
                booking.save(update_fields=['final_price', 'coupon_code', 'coupon_discount', 'updated_at'])
                total_discount += row_discount

            final_total += Decimal(booking.final_price)
            slot_for_sync = TimeSlot.objects.filter(id=booking.time_slot_id).first()
            if slot_for_sync is not None:
                _sync_to_supabase_async(slot=slot_for_sync, booking=booking)

        return Response(
            {
                'type': 'payment_success',
                'booking_ids': [booking.id for booking in created_bookings],
                'status': created_bookings[0].status if created_bookings else BookingStatus.CONFIRMED,
                'payment_status': created_bookings[0].payment_status if created_bookings else PaymentStatus.MOCK_PAID,
                'payment_channel': payment_channel,
                'payment_provider': payment_provider,
                'coupon_code': created_bookings[0].coupon_code if created_bookings else '',
                'coupon_discount_total': str(total_discount),
                'final_amount_total': str(final_total.quantize(Decimal('0.01'))),
            }
        )

    booking_ids = request.data.get('booking_ids')
    booking_id = request.data.get('booking_id')

    if booking_ids and isinstance(booking_ids, list):
        raw_ids = booking_ids
    elif booking_id is not None:
        raw_ids = [booking_id]
    else:
        return Response({'error': 'booking_id or booking_ids is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        normalized_ids = sorted({int(item) for item in raw_ids})
    except (TypeError, ValueError):
        return Response({'error': 'booking ids must be integers'}, status=status.HTTP_400_BAD_REQUEST)

    expired_ids = set(_release_expired_pending_bookings(user_uuid=user_uuid, booking_ids=normalized_ids))
    if expired_ids:
        return Response(
            {
                'error': f'Payment window expired ({PAYMENT_WINDOW_MINUTES} minutes). Please book again.',
                'type': 'payment_window_expired',
                'expired_booking_ids': sorted(expired_ids),
            },
            status=status.HTTP_409_CONFLICT,
        )

    bookings = list(Booking.objects.filter(id__in=normalized_ids, user_id=user_uuid).select_related('time_slot'))
    if len(bookings) != len(normalized_ids):
        return Response({'error': 'one or more bookings not found'}, status=status.HTTP_404_NOT_FOUND)

    slots_to_sync = []
    bookings_to_sync = []
    coupon = None
    discount_ratio = Decimal('0.00')
    applied_coupon_code = ''

    if coupon_code:
        now = timezone.now()
        coupon = Coupon.objects.filter(
            code=coupon_code,
            is_active=True,
            archived_at__isnull=True,
            starts_at__lte=now,
            ends_at__gte=now,
        ).first()
        if coupon is None:
            return Response({'error': 'Invalid or expired coupon code.'}, status=status.HTTP_400_BAD_REQUEST)
        discount_ratio = (Decimal(coupon.discount_percent) / Decimal('100')).quantize(Decimal('0.0001'))
        applied_coupon_code = coupon.code

    total_discount = Decimal('0.00')
    total_final = Decimal('0.00')
    with transaction.atomic():
        for booking in bookings:
            slot = TimeSlot.objects.select_for_update().get(id=booking.time_slot_id)
            slot.reservation_hold_until = None
            # Confirmed booking locks this slot for other accounts.
            slot.is_open = False
            slot.save(update_fields=['reservation_hold_until', 'is_open', 'availability_state', 'updated_at'])

            coupon_discount = Decimal('0.00')
            if coupon is not None:
                coupon_discount = (Decimal(booking.final_price) * discount_ratio).quantize(Decimal('0.01'))
                discounted_price = (Decimal(booking.final_price) - coupon_discount).quantize(Decimal('0.01'))
                if discounted_price < Decimal('0.00'):
                    discounted_price = Decimal('0.00')
                booking.final_price = discounted_price
                booking.coupon_code = applied_coupon_code
                booking.coupon_discount = coupon_discount
                total_discount += coupon_discount

            total_final += Decimal(booking.final_price)

            booking.payment_status = PaymentStatus.MOCK_PAID
            booking.status = BookingStatus.CONFIRMED
            booking.save(update_fields=['payment_status', 'status', 'final_price', 'coupon_code', 'coupon_discount', 'updated_at'])

            slots_to_sync.append(slot)
            bookings_to_sync.append(booking)

    for slot, booking in zip(slots_to_sync, bookings_to_sync):
        _sync_to_supabase_async(slot=slot, booking=booking)

    return Response(
        {
            'type': 'payment_success',
            'booking_ids': normalized_ids,
            'status': BookingStatus.CONFIRMED,
            'payment_status': PaymentStatus.MOCK_PAID,
            'payment_channel': payment_channel,
            'payment_provider': payment_provider,
            'coupon_code': applied_coupon_code,
            'coupon_discount_total': str(total_discount),
            'final_amount_total': str(total_final),
        }
    )


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


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
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
@permission_classes([IsAuthenticated])
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
@permission_classes([IsAuthenticated])
def owner_coupons_endpoint(request):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        now = timezone.now()
        archive_cutoff = _coupon_archive_cutoff(now)
        qs = Coupon.objects.filter(
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
@permission_classes([IsAuthenticated])
def owner_coupon_detail_endpoint(request, coupon_id):
    if not _is_owner_user(request.user):
        return Response({'error': 'Owner access required.'}, status=status.HTTP_403_FORBIDDEN)

    try:
        coupon = Coupon.objects.get(id=coupon_id)
    except Coupon.DoesNotExist:
        return Response({'error': 'Coupon not found.'}, status=status.HTTP_404_NOT_FOUND)

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
    
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def admin_set_role_endpoint(request):
    if not _is_admin_user(request.user):
        return Response({'error': 'Admin access required.'}, status=status.HTTP_403_FORBIDDEN)

    email = (request.data.get('email') or '').strip().lower()
    new_role = (request.data.get('role') or '').strip()
    if new_role not in ('user', 'owner', 'admin'):
        return Response({'error': 'Invalid role.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        target = User.objects.get(username=email)
    except User.DoesNotExist:
        return Response({'error': 'User not found.'}, status=status.HTTP_404_NOT_FOUND)

    if target.is_superuser:
        return Response({'error': 'Cannot change a superadmin.'}, status=status.HTTP_403_FORBIDDEN)

    if (new_role == 'admin' or _role_for_user(target) == 'admin') and not request.user.is_superuser:
        return Response({'error': 'Only a superadmin can manage admins.'}, status=status.HTTP_403_FORBIDDEN)

    Profile.objects.update_or_create(user=target, defaults={'role': new_role})
    return Response({'email': email, 'role': new_role})
