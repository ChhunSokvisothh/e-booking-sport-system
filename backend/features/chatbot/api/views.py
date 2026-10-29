import logging
import re

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import Booking, BookingSource, ChatMessage, ChatSession, TimeSlot
from global_utils.view_helpers import (
    PAYMENT_WINDOW_MINUTES,
    _build_payment_quote_payload,
    _build_suggestions,
    _call_ai_extractor,
    _canonicalize_target_for_quote,
    _chat_request_summary,
    _chatbot_display_venue_name,
    _create_pending_booking,
    _extract_facility_hint_from_message,
    _extracted_from_suggestion,
    _fallback_extract_from_message,
    _faq_answer,
    _find_facility_name_in_message,
    _is_alternative_browse_query,
    _is_list_all_slots_query,
    _is_payment_status_query,
    _is_target_currently_available,
    _keyword_intent_hint,
    _load_chat_context,
    _looks_like_exact_confirm,
    _matched_venue_prefix,
    _merge_extracted,
    _merge_with_chat_context,
    _nearest_suggestions,
    _payment_deadline_for_booking,
    _payment_status_payload,
    _range_mode_prefix,
    _reference_option_index_from_message,
    _release_expired_pending_bookings,
    _requested_slot_count,
    _resolve_active_facility_from_hint,
    _save_chat_context,
    _suggest_venue_names_from_hint,
    _uuid_from_user,
)

logger = logging.getLogger(__name__)

def _persist_chat_response(view):
    def wrapped(request, *args, **kwargs):
        response = view(request, *args, **kwargs)
        session_id = (request.data.get('chatbot_session_id') or '').strip()
        if session_id and hasattr(response, 'data') and isinstance(response.data, dict):
            content = response.data.get('text') or response.data.get('error') or ''
            if content:
                try:
                    session = ChatSession.objects.get(
                        session_id=session_id,
                        user_id=_uuid_from_user(request.user),
                    )
                    ChatMessage.objects.create(
                        session=session,
                        role=ChatMessage.Role.ASSISTANT,
                        content=str(content),
                    )
                except ChatSession.DoesNotExist:
                    logger.warning('Unable to persist response for unknown chat session %s', session_id)
                except Exception:
                    # A history write must never turn a valid AI response into a 500.
                    logger.exception('Unable to persist chat response for session %s', session_id)
        return response
    return wrapped

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def chat_sessions_endpoint(request):
    user_id = _uuid_from_user(request.user)
    sessions = ChatSession.objects.filter(user_id=user_id).prefetch_related('messages')[:50]
    return Response(
        [
            {
                'session_id': item.session_id,
                'title': item.title or 'AI Booking Session',
                'created_at': item.created_at,
                'last_message_at': item.last_message_at,
                'message_count': item.messages.count(),
            }
            for item in sessions
        ]
    )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def chat_session_messages_endpoint(request, session_id):
    user_id = _uuid_from_user(request.user)
    try:
        session = ChatSession.objects.get(session_id=session_id, user_id=user_id)
    except ChatSession.DoesNotExist:
        return Response({'error': 'Chat session not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response(
        [
            {
                'role': message.role,
                'content': message.content,
                'created_at': message.created_at,
            }
            for message in session.messages.all()
        ]
    )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@_persist_chat_response
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
        if chatbot_session_id:
            session, _ = ChatSession.objects.get_or_create(
                session_id=chatbot_session_id,
                defaults={'user_id': user_id, 'title': message[:160]},
            )
            if session.user_id != user_id:
                return Response({'error': 'Chat session does not belong to this account.'}, status=status.HTTP_403_FORBIDDEN)
            ChatMessage.objects.create(session=session, role=ChatMessage.Role.USER, content=message)
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
            payload = _payment_status_payload(booking)
            return Response(payload)

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
        logger.exception(
            'Chat request failed user_id=%s session_id=%s',
            getattr(request.user, 'pk', None),
            request.data.get('chatbot_session_id'),
        )
        return Response(
            {
                'error': 'I could not complete that request right now. Please try again.',
                'type': 'chat_error',
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
