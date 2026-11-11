import 'dart:convert';

import 'package:intl/intl.dart';

import '../../shared/models/models.dart';

String bookingReceiptId(BookingItem booking) {
  final datePart = DateFormat('yyyyMMdd').format(booking.startAt.toLocal());
  return 'RCPT-$datePart-${booking.id.toString().padLeft(5, '0')}';
}

String bookingCheckinPayload(BookingItem booking) {
  return booking.checkinToken;
}
