from .common import *
from .chatbot_parsing import *
from .slot_helpers import _ensure_rolling_slot_window_cached

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


__all__ = [name for name in globals() if not name.startswith("__")]
