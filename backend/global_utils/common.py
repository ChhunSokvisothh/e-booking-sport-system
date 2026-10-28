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

from core.models import Booking, BookingSource, BookingStatus, Coupon, Facility, OwnerSubscription, PaymentStatus, SportType, TimeSlot
from core.serializers import BookingSerializer, CouponSerializer, FacilitySerializer, TimeSlotSerializer

User = get_user_model()
BOOKING_WINDOW_DAYS = 15
ROLLING_SLOT_REFRESH_SECONDS = 60
PAYMENT_WINDOW_MINUTES = 5
COUPON_ARCHIVE_RETENTION_DAYS = 90
FACILITY_ARCHIVE_RETENTION_DAYS = 90

class FacilityPagination(PageNumberPagination):
    page_size = 12
    page_size_query_param = 'page_size'
    max_page_size = 40

class SlotPagination(PageNumberPagination):
    page_size = 24
    page_size_query_param = 'page_size'
    max_page_size = 80


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
    return 'owner' if _is_owner_user(user) else 'user'

def _is_owner_user(user):
    if not user:
        return False
    if user.is_staff or user.is_superuser:
        return True
    owner_uuid = _uuid_from_user(user)
    return OwnerSubscription.objects.filter(
        user_id=owner_uuid,
        status='active',
        expires_at__gt=timezone.now(),
    ).exists()

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

__all__ = [name for name in globals() if not name.startswith("__")]
