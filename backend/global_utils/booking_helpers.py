from .common import *

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


__all__ = [name for name in globals() if not name.startswith("__")]
