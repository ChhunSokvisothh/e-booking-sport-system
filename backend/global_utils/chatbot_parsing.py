from .common import *

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

    try:
        rain = _rain_mm(lat, lng, date_str)
    except Exception:
        # Weather is optional; keep slot search available when the provider is unreachable.
        rain = 0.0
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


__all__ = [name for name in globals() if not name.startswith("__")]
