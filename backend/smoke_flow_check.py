from __future__ import annotations

import json
import os
import sys
import uuid
from dataclasses import dataclass
from decimal import Decimal

import django
from django.db import models

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from core.models import Booking, BookingStatus, PaymentStatus, TimeSlot


@dataclass
class StepResult:
    name: str
    ok: bool
    details: str


def _add(results: list[StepResult], name: str, ok: bool, details: str) -> None:
    results.append(StepResult(name=name, ok=ok, details=details))
    print(f"[{ 'PASS' if ok else 'FAIL' }] {name}: {details}")


def main() -> int:
    results: list[StepResult] = []

    if "testserver" not in settings.ALLOWED_HOSTS:
        settings.ALLOWED_HOSTS = [*settings.ALLOWED_HOSTS, "testserver"]

    slot = (
        TimeSlot.objects.select_related("facility")
        .filter(is_open=True, start_at__gt=timezone.now())
        .filter(current_bookings__lt=models.F("max_bookings"))
        .order_by("start_at")
        .first()
    )
    if slot is None:
        _add(
            results,
            "Find available future slot",
            False,
            "No open future slot with free capacity found in local DB.",
        )
        _summary(results)
        return 1

    original_current = slot.current_bookings
    _add(
        results,
        "Find available future slot",
        True,
        f"slot_id={slot.id}, facility={slot.facility.name}, start={slot.start_at.isoformat()}, current={slot.current_bookings}/{slot.max_bookings}",
    )

    user_email = f"smoke.{uuid.uuid4().hex[:8]}@example.com"
    user_password = "SmokePass123!"
    user_model = get_user_model()
    user = user_model.objects.create_user(username=user_email, email=user_email, password=user_password)
    token, _ = Token.objects.get_or_create(user=user)

    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    duration_hours = Decimal((slot.end_at - slot.start_at).total_seconds() / 3600).quantize(Decimal("0.01"))
    if duration_hours <= 0:
        duration_hours = Decimal("1.00")

    base_price = (slot.facility.base_price_per_hour * duration_hours).quantize(Decimal("0.01"))

    suggestion = {
        "option_id": f"{slot.facility_id}:{slot.id}:{duration_hours}",
        "facility_name": slot.facility.name,
        "start_at": slot.start_at.isoformat(),
        "duration_hours": float(duration_hours),
        "base_price": str(base_price),
        "weather_discount": "0.00",
        "empty_slot_discount": "0.00",
        "final_price": str(base_price),
        "currency": "USD",
        "rain_mm": 0,
    }

    chat_resp = client.post(
        "/api/chat/",
        data={
            "message": "confirm",
            "booking_source": "manual",
            "selected_option_id": suggestion["option_id"],
            "suggestions": [suggestion],
        },
        format="json",
    )

    if chat_resp.status_code != 201:
        _add(
            results,
            "Create pending booking via chat confirm",
            False,
            f"Unexpected status={chat_resp.status_code}, body={chat_resp.content.decode('utf-8', 'ignore')[:200]}",
        )
        _summary(results)
        return 1

    payload = chat_resp.json()
    booking_id = payload.get("booking_id")
    booking = Booking.objects.get(id=booking_id)
    slot.refresh_from_db()

    pending_ok = (
        booking.status == BookingStatus.PENDING
        and booking.payment_status == PaymentStatus.MOCK_PENDING
        and slot.current_bookings == original_current + 1
        and booking.time_slot_id == slot.id
        and slot.reservation_hold_until is not None
        and slot.reservation_hold_until > timezone.now()
    )
    _add(
        results,
        "Create pending booking via chat confirm",
        pending_ok,
        f"booking_id={booking_id}, status={booking.status}, payment={booking.payment_status}, slot_count={slot.current_bookings}/{slot.max_bookings}",
    )

    pay_resp = client.post("/api/mock-payment/", data={"booking_id": booking_id}, format="json")
    if pay_resp.status_code != 200:
        _add(
            results,
            "Confirm payment",
            False,
            f"Unexpected status={pay_resp.status_code}, body={pay_resp.content.decode('utf-8', 'ignore')[:200]}",
        )
        _summary(results)
        return 1

    booking.refresh_from_db()
    slot.refresh_from_db()
    paid_ok = (
        booking.status == BookingStatus.CONFIRMED
        and booking.payment_status == PaymentStatus.MOCK_PAID
        and slot.current_bookings == original_current + 1
        and slot.reservation_hold_until is None
    )
    _add(
        results,
        "Confirm payment",
        paid_ok,
        f"status={booking.status}, payment={booking.payment_status}, slot_count={slot.current_bookings}/{slot.max_bookings}, hold={slot.reservation_hold_until}",
    )

    hist_resp = client.get("/api/bookings/")
    if hist_resp.status_code != 200:
        _add(results, "Booking appears in history", False, f"Unexpected status={hist_resp.status_code}")
        _summary(results)
        return 1

    hist_json = hist_resp.json()
    history_items = hist_json.get("results", hist_json if isinstance(hist_json, list) else [])
    in_history = any(int(item.get("id", -1)) == int(booking_id) for item in history_items)
    _add(
        results,
        "Booking appears in history",
        in_history,
        f"history_count={len(history_items)}, booking_id={booking_id}",
    )

    cancel_resp = client.post(f"/api/bookings/{booking_id}/cancel/")
    if cancel_resp.status_code != 200:
        _add(
            results,
            "Cancel booking",
            False,
            f"Unexpected status={cancel_resp.status_code}, body={cancel_resp.content.decode('utf-8', 'ignore')[:200]}",
        )
        _summary(results)
        return 1

    booking.refresh_from_db()
    slot.refresh_from_db()
    cancel_ok = booking.status == BookingStatus.CANCELLED and slot.current_bookings == original_current
    _add(
        results,
        "Cancel booking",
        cancel_ok,
        f"status={booking.status}, payment={booking.payment_status}, slot_count={slot.current_bookings}/{slot.max_bookings}",
    )

    # Cleanup test user/token/booking artifacts
    Booking.objects.filter(id=booking_id).delete()
    Token.objects.filter(user=user).delete()
    user.delete()

    _summary(results)
    return 0 if all(r.ok for r in results) else 2


def _summary(results: list[StepResult]) -> None:
    total = len(results)
    passed = sum(1 for r in results if r.ok)
    failed = total - passed
    print("\n=== Smoke Flow Summary ===")
    print(json.dumps({"total": total, "passed": passed, "failed": failed}, indent=2))


if __name__ == "__main__":
    raise SystemExit(main())
