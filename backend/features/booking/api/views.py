from datetime import timezone as dt_timezone
from decimal import Decimal

from django.db import models, transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import Booking, BookingSource, BookingStatus, Coupon, PaymentStatus, TimeSlot
from core.serializers import BookingSerializer
from global_utils.view_helpers import (
    PAYMENT_WINDOW_MINUTES,
    _create_confirmed_booking_from_target,
    _create_pending_booking,
    _ensure_rolling_slot_window_cached,
    _extracted_from_suggestion,
    _nearest_suggestions,
    _release_expired_pending_bookings,
    _sync_to_supabase_async,
    _target_option_chunks,
    _uuid_from_user,
)

class BookingViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = BookingSerializer
    queryset = Booking.objects.select_related('facility', 'time_slot').all()
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        if not (self.request.user.is_staff or self.request.user.is_superuser):
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


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def manual_booking_endpoint(request):
    slot_id = request.data.get('slot_id')
    if slot_id in (None, ''):
        return Response({'error': 'slot_id is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        slot = TimeSlot.objects.select_related('facility').get(
            id=slot_id,
            facility__is_active=True,
            is_open=True,
        )
    except (TimeSlot.DoesNotExist, ValueError, TypeError):
        return Response({'error': 'Slot not found or no longer available.'}, status=status.HTTP_404_NOT_FOUND)

    price = Decimal(str(slot.facility.base_price_per_hour))
    target = {
        'option_id': f'{slot.facility_id}:{slot.id}:1',
        'facility_name': slot.facility.name,
        'start_at': slot.start_at.isoformat(),
        'duration_hours': 1,
        'base_price': str(price),
        'weather_discount': '0.00',
        'empty_slot_discount': '0.00',
        'final_price': str(price),
        'rain_mm': 0,
    }

    try:
        booking = _create_pending_booking(
            target,
            user_uuid=_uuid_from_user(request.user),
            booking_source=BookingSource.MANUAL,
        )
    except TimeSlot.DoesNotExist:
        return Response({'error': 'Slot not found or no longer available.'}, status=status.HTTP_404_NOT_FOUND)
    except ValueError as ex:
        return Response({'error': str(ex)}, status=status.HTTP_409_CONFLICT)

    return Response(
        {
            'type': 'pending_booking_created',
            'booking_id': booking.id,
            'status': booking.status,
            'payment_status': booking.payment_status,
            'final_price': str(booking.final_price),
            'currency': 'USD',
        },
        status=status.HTTP_201_CREATED,
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
        refund_amount = Decimal('0.00')
        if booking.payment_status == PaymentStatus.MOCK_PAID and booking.start_at > timezone.now():
            refund_amount = booking.final_price
            booking.refund_amount = refund_amount
            booking.refunded_at = timezone.now()
        if booking.payment_status == PaymentStatus.MOCK_PENDING:
            booking.payment_status = PaymentStatus.MOCK_FAILED
        booking.save(update_fields=['status', 'payment_status', 'refund_amount', 'refunded_at', 'updated_at'])

    _sync_to_supabase_async(slot=slot, booking=booking)

    return Response(
        {
            'type': 'booking_cancelled',
            'booking_id': booking.id,
            'status': booking.status,
            'payment_status': booking.payment_status,
            'refund_amount': str(booking.refund_amount),
            'refund_status': 'refunded' if booking.refund_amount > 0 else 'not_applicable',
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
        booking_source = str(request.data.get('booking_source') or BookingSource.CHATBOT).strip() or BookingSource.CHATBOT

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
