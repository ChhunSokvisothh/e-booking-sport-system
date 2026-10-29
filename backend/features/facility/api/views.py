from datetime import datetime, timedelta

from django.db import models
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from core.models import Facility, TimeSlot
from core.serializers import FacilitySerializer, TimeSlotSerializer
from global_utils.view_helpers import (
    FacilityPagination,
    SlotPagination,
    _booked_slot_ids_for_user,
    _availability_status,
    _date_bounds_for_query,
    _ensure_rolling_slot_window_cached,
    _release_expired_pending_bookings,
    _slot_payload,
)

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
    try:
        page = max(1, int(request.query_params.get('page', '1')))
    except ValueError:
        page = 1
    try:
        page_size = min(100, max(10, int(request.query_params.get('page_size', '50'))))
    except ValueError:
        page_size = 50

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
        return Response(
            {
                'count': 0,
                'page': page,
                'page_size': page_size,
                'has_next': False,
                'results': [],
            }
        )

    facility_map = {f.id: f for f in facilities}
    facility_map_by_str = {str(f.id): f for f in facilities}
    booked_slot_ids = _booked_slot_ids_for_user(request)

    local_qs = TimeSlot.objects.select_related('facility').filter(facility__in=facilities)
    if day_start is not None and day_end is not None:
        local_qs = local_qs.filter(start_at__gte=day_start, start_at__lt=day_end)
    if requested_date is None or requested_date == local_today:
        local_qs = local_qs.filter(start_at__gte=now)
    total_count = local_qs.count()
    local_slots = list(
        local_qs.order_by('start_at', 'id')[
            (page - 1) * page_size : page * page_size
        ]
    )
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
        availability_status = _availability_status(is_open, current, max_bookings, hold_until)
        is_available = availability_status in ['available', 'limited']

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
                'availability_status': availability_status,
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
        availability_status = _availability_status(
            slot.is_open,
            slot.current_bookings,
            slot.max_bookings,
            slot.reservation_hold_until,
        )
        is_available = availability_status in ['available', 'limited']
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
                'availability_status': availability_status,
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
                    'is_available': _availability_status(
                        slot.is_open,
                        slot.current_bookings,
                        slot.max_bookings,
                        slot.reservation_hold_until,
                    ) in ['available', 'limited'],
                    'availability_status': _availability_status(
                        slot.is_open,
                        slot.current_bookings,
                        slot.max_bookings,
                        slot.reservation_hold_until,
                    ),
                    'slot_version': slot.slot_version,
                    'reservation_hold_until': slot.reservation_hold_until,
                    'booked_by_me': str(slot.id) in booked_slot_ids,
                    'base_price_per_hour': float(slot.facility.base_price_per_hour),
                    'is_indoor': slot.facility.is_indoor,
                    'location_name': slot.facility.location_name,
                }
            )

    output.sort(key=lambda item: item['start_at'])
    return Response(
        {
            'count': total_count,
            'page': page,
            'page_size': page_size,
            'has_next': page * page_size < total_count,
            'results': output,
        }
    )


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
