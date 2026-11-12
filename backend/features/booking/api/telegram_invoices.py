import html
import os
import threading
from io import BytesIO
from urllib.parse import quote

import requests
from django.conf import settings
from django.core import signing
from django.db import transaction
from django.http import HttpResponse
from django.utils import timezone
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors
from reportlab.platypus import Flowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.models import Booking, BookingStatus, PaymentStatus, TelegramIdentity, TelegramInvoiceDelivery
from global_utils.common import _uuid_from_user


class _QRFlowable(Flowable):
    def __init__(self, value, size=104):
        super().__init__()
        self.value = value
        self.width = size
        self.height = size
        self.size = size

    def draw(self):
        widget = QrCodeWidget(self.value)
        bounds = widget.getBounds()
        width = bounds[2] - bounds[0]
        height = bounds[3] - bounds[1]
        drawing = Drawing(self.size, self.size, transform=[self.size / width, 0, 0, self.size / height, 0, 0])
        drawing.add(widget)
        from reportlab.graphics import renderPDF
        renderPDF.draw(drawing, self.canv, 0, 0)


def _public_invoice_url(bookings):
    booking_ids = sorted({int(booking.id) for booking in bookings})
    token = signing.dumps({'booking_ids': booking_ids}, salt='public-booking-invoice-v1', compress=True)
    base_url = (
        getattr(settings, 'PUBLIC_INVOICE_BASE_URL', '')
        or os.getenv('PUBLIC_INVOICE_BASE_URL', '')
        or getattr(settings, 'BACKEND_URL', '')
    ).rstrip('/')
    return f'{base_url}/api/public/invoice/{quote(token, safe="")}/' if base_url else ''


def _directions_url(facility):
    if facility.latitude and facility.longitude:
        return f'https://www.google.com/maps/dir/?api=1&destination={facility.latitude},{facility.longitude}'
    destination = quote(f'{facility.name}, {facility.location_name}')
    return f'https://www.google.com/maps/dir/?api=1&destination={destination}'


def _build_combined_invoice_pdf(bookings, receipt_id, invoice_url):
    output = BytesIO()
    doc = SimpleDocTemplate(output, pagesize=A4, title=f'Booking invoice {receipt_id}')
    styles = getSampleStyleSheet()
    safe = lambda value: html.escape(str(value))
    facility = bookings[0].facility
    total = sum((booking.final_price for booking in bookings), start=bookings[0].final_price * 0)
    rows = [['Booking', 'Date', 'Time', 'Field/Table', 'Amount']]
    for booking in bookings:
        start, end = timezone.localtime(booking.start_at), timezone.localtime(booking.end_at)
        court_label = 'Table' if facility.sport_type == 'billiard' else 'Field'
        rows.append([
            f'#{booking.id}',
            start.strftime('%d %b %Y'),
            f'{start:%H:%M}–{end:%H:%M}',
            f'{court_label} {booking.time_slot.court_number}',
            f'USD {booking.final_price:.2f}',
        ])
    table = Table(rows, repeatRows=1, colWidths=[55, 85, 90, 90, 80])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E8EEF7')),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#CBD5E1')),
        ('PADDING', (0, 0), (-1, -1), 7),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ]))
    directions = _directions_url(facility)
    story = [
        Paragraph('E-Booking Sport System', styles['Title']),
        Paragraph('Combined Booking Payment Invoice', styles['Heading2']),
        Paragraph(f'<b>Receipt ID:</b> {safe(receipt_id)}', styles['BodyText']),
        Paragraph(f'<b>Venue:</b> {safe(facility.name)}', styles['BodyText']),
        Paragraph(f'<b>Address:</b> {safe(facility.location_name)}', styles['BodyText']),
        Paragraph(f'<b>Sport:</b> {safe(facility.sport_type.title())}', styles['BodyText']),
        Spacer(1, 12), table, Spacer(1, 12),
        Paragraph(f'<b>Total paid:</b> USD {total:.2f}', styles['Heading2']),
        Paragraph('<b>Payment status:</b> PAID', styles['BodyText']),
        Spacer(1, 16),
        Paragraph(f'<b>Venue directions:</b> <link href="{safe(directions)}" color="blue">Open directions in Google Maps</link>', styles['BodyText']),
        Spacer(1, 14),
    ]
    # The invoice URL and the venue check-in token serve different purposes.
    # Never encode the public invoice URL as the venue check-in QR.
    story.extend([
        Paragraph('<b>Venue check-in QR codes</b>', styles['Heading3']),
        Paragraph('Show the QR for the relevant booking to venue staff. Each QR can be used once.', styles['BodyText']),
        Spacer(1, 6),
    ])
    for booking in bookings:
        checkin_token = signing.dumps({'booking_id': booking.id}, salt='booking-checkin')
        story.extend([
            Paragraph(f'<b>Booking #{booking.id} — Check-in</b>', styles['BodyText']),
            Spacer(1, 4),
            _QRFlowable(checkin_token, size=112),
            Spacer(1, 10),
        ])
    if invoice_url:
        story.extend([
            Paragraph(f'<link href="{safe(invoice_url)}" color="blue">Open secure online invoice</link>', styles['BodyText']),
            Paragraph('The online invoice link is read-only and expires after 30 days.', styles['Italic']),
        ])
    else:
        story.append(Paragraph('Online invoice link unavailable: configure PUBLIC_INVOICE_BASE_URL.', styles['Italic']))
    doc.build(story)
    output.seek(0)
    return output


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


def deliver_paid_bookings_invoice(booking_ids):
    """Deliver one combined receipt for all bookings in a single checkout."""
    ids = sorted({int(value) for value in booking_ids})
    bookings = list(
        Booking.objects.filter(id__in=ids)
        .select_related('facility', 'time_slot')
        .order_by('start_at', 'id')
    )
    if not ids or len(bookings) != len(ids):
        return {'status': 'skipped', 'reason': 'Bookings not found.'}
    if len({b.user_id for b in bookings}) != 1 or any(
        b.payment_status != PaymentStatus.MOCK_PAID or b.status != BookingStatus.CONFIRMED
        for b in bookings
    ):
        return {'status': 'skipped', 'reason': 'Bookings must belong to one user and be confirmed/paid.'}

    identity = next(
        (item for item in TelegramIdentity.objects.select_related('user').all()
         if _uuid_from_user(item.user) == bookings[0].user_id),
        None,
    )
    if identity is None:
        return {'status': 'not_linked', 'reason': 'No Telegram account is linked.'}

    with transaction.atomic():
        deliveries = [
            TelegramInvoiceDelivery.objects.get_or_create(
                booking=b,
                defaults={'user': identity.user, 'status': TelegramInvoiceDelivery.Status.PENDING},
        )[0] for b in bookings
        ]
    receipt_id = f'EB-{min(ids):06d}'
    if all(d.status == TelegramInvoiceDelivery.Status.SENT for d in deliveries):
        return {'status': 'sent', 'receipt_id': receipt_id}

    error = ''
    token = getattr(settings, 'TELEGRAM_BOT_TOKEN', '')
    if not token:
        error = 'TELEGRAM_BOT_TOKEN is not configured.'
    else:
        total = sum((b.final_price for b in bookings), start=bookings[0].final_price * 0)
        lines = [
            '✅ <b>Booking payment confirmed</b>',
            f'Receipt: <code>{receipt_id}</code>',
            f'Bookings: {len(bookings)} time slot(s)',
            f'Venue: {html.escape(bookings[0].facility.name)}',
            f'Sport: {html.escape(bookings[0].facility.sport_type.title())}',
        ]
        for b in bookings:
            start, end = timezone.localtime(b.start_at), timezone.localtime(b.end_at)
            court_label = 'Table' if b.facility.sport_type == 'billiard' else 'Field'
            lines.append(f'• {start:%d %b %Y} {start:%H:%M}–{end:%H:%M} ({court_label} {b.time_slot.court_number}) — USD {b.final_price:.2f}')
        lines.append(f'<b>Total paid: USD {total:.2f}</b>')
        base = f'https://api.telegram.org/bot{token}'
        try:
            invoice_url = _public_invoice_url(bookings)
            if invoice_url:
                lines.append(f'Invoice: {html.escape(invoice_url)}')
            directions = _directions_url(bookings[0].facility)
            lines.append(f'Directions: {html.escape(directions)}')
            response = requests.post(
                f'{base}/sendMessage',
                json={'chat_id': identity.telegram_user_id, 'text': '\n'.join(lines), 'parse_mode': 'HTML'},
                timeout=10,
            )
            response.raise_for_status()

            output = _build_combined_invoice_pdf(bookings, receipt_id, invoice_url)
            response = requests.post(
                f'{base}/sendDocument',
                data={'chat_id': identity.telegram_user_id, 'caption': f'Invoice {receipt_id} — {len(bookings)} booking(s)'},
                files={'document': (f'{receipt_id}.pdf', output, 'application/pdf')},
                timeout=20,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            error = f'Telegram delivery failed: {exc}'
        except Exception as exc:
            error = f'Invoice generation/delivery failed: {exc}'

    with transaction.atomic():
        for delivery in deliveries:
            delivery.attempts += 1
            delivery.last_error = error
            delivery.status = TelegramInvoiceDelivery.Status.FAILED if error else TelegramInvoiceDelivery.Status.SENT
            delivery.sent_at = None if error else timezone.now()
            delivery.save(update_fields=['attempts', 'last_error', 'status', 'sent_at', 'updated_at'])
    return {'status': TelegramInvoiceDelivery.Status.FAILED if error else TelegramInvoiceDelivery.Status.SENT, 'receipt_id': receipt_id, 'error': error}


def deliver_paid_booking_invoice(booking_id):
    return deliver_paid_bookings_invoice([booking_id])


def deliver_paid_bookings_invoice_async(booking_ids):
    ids = tuple(sorted({int(value) for value in booking_ids}))
    if ids:
        threading.Thread(target=deliver_paid_bookings_invoice, args=(ids,), daemon=True).start()


def deliver_paid_booking_invoice_async(booking_id):
    return deliver_paid_bookings_invoice_async([booking_id])


@api_view(['GET'])
@permission_classes([AllowAny])
def public_booking_invoice(request, token):
    """Read-only invoice page opened by the QR code; the signed token expires after 30 days."""
    try:
        payload = signing.loads(token, salt='public-booking-invoice-v1', max_age=60 * 60 * 24 * 30)
        booking_ids = sorted({int(value) for value in payload.get('booking_ids', [])})
    except (signing.BadSignature, signing.SignatureExpired, TypeError, ValueError, AttributeError):
        return HttpResponse('This invoice link is invalid or has expired.', status=410)

    bookings = list(
        Booking.objects.filter(
            id__in=booking_ids,
            payment_status=PaymentStatus.MOCK_PAID,
            status=BookingStatus.CONFIRMED,
        ).select_related('facility', 'time_slot').order_by('start_at', 'id')
    )
    if not booking_ids or len(bookings) != len(booking_ids):
        return HttpResponse('Invoice not found or no longer available.', status=404)
    if len({booking.facility_id for booking in bookings}) != 1 or len({booking.user_id for booking in bookings}) != 1:
        return HttpResponse('Invalid invoice group.', status=400)

    facility = bookings[0].facility
    total = sum((booking.final_price for booking in bookings), start=bookings[0].final_price * 0)
    receipt_id = f'EB-{min(booking_ids):06d}'
    directions = _directions_url(facility)
    rows = ''.join(
        '<tr><td>#{}</td><td>{}</td><td>{}–{}</td><td>{} {}</td><td>USD {:.2f}</td></tr>'.format(
            booking.id,
            timezone.localtime(booking.start_at).strftime('%d %b %Y'),
            timezone.localtime(booking.start_at).strftime('%H:%M'),
            timezone.localtime(booking.end_at).strftime('%H:%M'),
            'Table' if facility.sport_type == 'billiard' else 'Field',
            booking.time_slot.court_number,
            booking.final_price,
        )
        for booking in bookings
    )
    page = f'''<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Booking invoice {html.escape(receipt_id)}</title>
    <style>
      body{{font:16px Arial,sans-serif;background:#f3f5f8;color:#172033;margin:0;padding:24px}}
      main{{max-width:760px;margin:24px auto;background:white;padding:28px;border-radius:16px;box-shadow:0 8px 30px #15223812}}
      h1{{font-size:24px}} .paid{{color:#087443;font-weight:bold}} table{{width:100%;border-collapse:collapse;margin:24px 0}}
      th,td{{padding:12px 8px;border-bottom:1px solid #e5e9ef;text-align:left}} a{{color:#075fbd}}
      .total{{font-size:22px;font-weight:bold;text-align:right}} @media(max-width:560px){{body{{padding:8px}}main{{padding:16px}}th,td{{font-size:12px;padding:8px 4px}}}}
    </style><body><main><h1>E-Booking Sport System</h1><h2>Booking payment invoice</h2>
    <p><b>Receipt:</b> {html.escape(receipt_id)}</p><p><b>Venue:</b> {html.escape(facility.name)}</p>
    <p><b>Address:</b> {html.escape(facility.location_name)}</p><p class="paid">Payment confirmed</p>
    <table><thead><tr><th>Booking</th><th>Date</th><th>Time</th><th>Field/Table</th><th>Amount</th></tr></thead>
    <tbody>{rows}</tbody></table><p class="total">Total paid: USD {total:.2f}</p>
    <p><a href="{html.escape(directions, quote=True)}" target="_blank" rel="noopener">Get venue directions in Google Maps</a></p>
    <small>This is a read-only invoice link. It expires 30 days after issue.</small></main></body></html>'''
    return HttpResponse(page)


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
