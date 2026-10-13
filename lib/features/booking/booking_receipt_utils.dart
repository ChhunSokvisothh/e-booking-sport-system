import 'dart:convert';

import 'package:intl/intl.dart';

import '../../core/models.dart';

String bookingReceiptId(BookingItem booking) {
  final datePart = DateFormat('yyyyMMdd').format(booking.startAt.toLocal());
  return 'RCPT-$datePart-${booking.id.toString().padLeft(5, '0')}';
}

String bookingCheckinPayload(BookingItem booking) {
  return jsonEncode({
    'receipt_id': bookingReceiptId(booking),
    'booking_id': booking.id,
    'facility_name': booking.facilityName,
    'start_at': booking.startAt.toIso8601String(),
    'end_at': booking.endAt.toIso8601String(),
    'status': booking.status,
    'payment_status': booking.paymentStatus,
    'booking_source': booking.bookingSource,
  });
}
