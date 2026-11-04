import html
from io import BytesIO

import requests
from django.conf import settings
from django.db import transaction
from django.utils import timezone
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import Booking, BookingStatus, PaymentStatus, TelegramIdentity, TelegramInvoiceDelivery
from global_utils.common import _uuid_from_user


def _build_invoice_pdf(booking, receipt_id):
    output = BytesIO()
    doc = SimpleDocTemplate(output, pagesize=A4, title=f'Booking invoice {receipt_id}')
    styles = getSampleStyleSheet()
    safe = lambda value: html.escape(str(value))
    story = [
        Paragraph('E-Booking Sport System', styles['Title']),
        Paragraph('Booking Payment Invoice', styles['Heading2']),
        Spacer(1, 12),
        Paragraph(f'<b>Receipt ID:</b> {safe(receipt_id)}', styles['BodyText']),
        Paragraph(f'<b>Booking ID:</b> {safe(booking.id)}', styles['BodyText']),
        Paragraph(f'<b>Venue:</b> {safe(booking.facility.name)}', styles['BodyText']),
        Paragraph(f'<b>Location:</b> {safe(booking.facility.location_name)}', styles['BodyText']),
        Paragraph(f'<b>Sport:</b> {safe(booking.facility.sport_type.title())}', styles['BodyText']),
        Paragraph(f'<b>Start:</b> {safe(timezone.localtime(booking.start_at).strftime("%d %b %Y, %H:%M"))}', styles['BodyText']),
        Paragraph(f'<b>End:</b> {safe(timezone.localtime(booking.end_at).strftime("%d %b %Y, %H:%M"))}', styles['BodyText']),
        Paragraph(f'<b>Payment status:</b> {safe(booking.payment_status)}', styles['BodyText']),
        Paragraph(f'<b>Booking status:</b> {safe(booking.status)}', styles['BodyText']),
        Spacer(1, 10),
        Paragraph(f'<b>Total paid:</b> USD {booking.final_price:.2f}', styles['Heading2']),
    ]
    if booking.coupon_code:
        story.append(Paragraph(f'<b>Coupon:</b> {safe(booking.coupon_code)} (discount USD {booking.coupon_discount:.2f})', styles['BodyText']))
    doc.build(story)
    output.seek(0)
    return output


def deliver_paid_booking_invoice(booking_id):
    """Best-effort delivery. Persist failures so a user can retry; never change payment state."""
    booking = Booking.objects.select_related('facility', 'time_slot').filter(pk=booking_id).first()
    if not booking or booking.payment_status != PaymentStatus.MOCK_PAID or booking.status != BookingStatus.CONFIRMED:
        return {'status': 'skipped', 'reason': 'Booking is not confirmed and paid.'}

    identity = next(
        (item for item in TelegramIdentity.objects.select_related('user').all()
         if _uuid_from_user(item.user) == booking.user_id),
        None,
    )
    if identity is None:
        return {'status': 'not_linked', 'reason': 'No Telegram account is linked to this booking user.'}

    delivery, _ = TelegramInvoiceDelivery.objects.get_or_create(
        booking=booking,
        defaults={'user': identity.user, 'status': TelegramInvoiceDelivery.Status.PENDING},
    )
    if delivery.status == TelegramInvoiceDelivery.Status.SENT:
        return {'status': 'sent', 'receipt_id': f'EB-{booking.id:06d}'}

    receipt_id = f'EB-{booking.id:06d}'
    token = getattr(settings, 'TELEGRAM_BOT_TOKEN', '')
    chat_id = identity.telegram_user_id
    if not token:
        error = 'TELEGRAM_BOT_TOKEN is not configured.'
    else:
        summary = (
            f'✅ <b>Booking payment confirmed</b>\n'
            f'Receipt: <code>{receipt_id}</code>\n'
            f'Booking: #{booking.id}\n'
            f'Venue: {html.escape(booking.facility.name)}\n'
            f'Sport: {html.escape(booking.facility.sport_type.title())}\n'
            f'Date: {timezone.localtime(booking.start_at).strftime("%d %b %Y")}\n'
            f'Time: {timezone.localtime(booking.start_at).strftime("%H:%M")}–{timezone.localtime(booking.end_at).strftime("%H:%M")}\n'
            f'Total paid: <b>USD {booking.final_price:.2f}</b>\n'
            f'Payment: {html.escape(booking.payment_status)}'
        )
        try:
            base = f'https://api.telegram.org/bot{token}'
            response = requests.post(
                f'{base}/sendMessage',
                json={'chat_id': chat_id, 'text': summary, 'parse_mode': 'HTML'},
                timeout=10,
            )
            response.raise_for_status()
            pdf = _build_invoice_pdf(booking, receipt_id)
            response = requests.post(
                f'{base}/sendDocument',
                data={'chat_id': chat_id, 'caption': f'Invoice {receipt_id}'},
                files={'document': (f'{receipt_id}.pdf', pdf, 'application/pdf')},
                timeout=20,
            )
            response.raise_for_status()
            error = ''
        except requests.RequestException as exc:
            error = f'Telegram delivery failed: {exc}'
        except Exception as exc:
            error = f'Invoice generation/delivery failed: {exc}'

    with transaction.atomic():
        delivery.attempts += 1
        delivery.last_error = error
        delivery.status = TelegramInvoiceDelivery.Status.FAILED if error else TelegramInvoiceDelivery.Status.SENT
        delivery.sent_at = None if error else timezone.now()
        delivery.save(update_fields=['attempts', 'last_error', 'status', 'sent_at', 'updated_at'])
    return {'status': delivery.status, 'receipt_id': receipt_id, 'error': error}


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def retry_telegram_invoice(request, booking_id):
    booking = Booking.objects.filter(pk=booking_id, user_id=_uuid_from_user(request.user)).first()
    if not booking:
        return Response({'error': 'Booking not found.'}, status=status.HTTP_404_NOT_FOUND)
    if booking.payment_status != PaymentStatus.MOCK_PAID or booking.status != BookingStatus.CONFIRMED:
        return Response({'error': 'Only confirmed, paid bookings can receive an invoice.'}, status=status.HTTP_409_CONFLICT)
    result = deliver_paid_booking_invoice(booking.id)
    if result['status'] == 'not_linked':
        return Response({'error': 'Link your Telegram account before requesting invoice delivery.'}, status=status.HTTP_409_CONFLICT)
    if result['status'] != 'sent':
        return Response({'error': result.get('error') or 'Telegram delivery failed. Please retry later.'}, status=status.HTTP_502_BAD_GATEWAY)
    return Response({'status': 'sent', 'receipt_id': result['receipt_id']})
