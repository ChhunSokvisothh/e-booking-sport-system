from .common import *

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

def _availability_status(is_open, current_bookings, max_bookings, reservation_hold_until=None):
    if reservation_hold_until and reservation_hold_until > timezone.now():
        return 'held'
    return _slot_status(is_open, current_bookings, max_bookings)


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
    status = _availability_status(is_open, current_bookings, max_bookings, hold_until)
    if current_bookings > 0 and status in ['available', 'limited']:
        status = 'full'
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


__all__ = [name for name in globals() if not name.startswith("__")]
