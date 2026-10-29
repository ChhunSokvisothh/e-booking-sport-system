import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../facility/facility_providers.dart';

final bookingHistoryProvider = FutureProvider<List<BookingItem>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return [];
  }

  final client = ref.watch(apiClientProvider);
  final list = await client.getList('/api/bookings/', null, session.token);
  return list.map((e) => BookingItem.fromJson(e as Map<String, dynamic>)).toList();
});

final activeCouponsProvider = FutureProvider<List<CouponItem>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return [];
  }

  final client = ref.watch(apiClientProvider);
  final list = await client.getList('/api/coupons/active/', null, session.token);
  return list.map((e) => CouponItem.fromJson(e as Map<String, dynamic>)).toList();
});

final ownerCouponsProvider = FutureProvider<List<CouponItem>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return [];
  }

  final client = ref.watch(apiClientProvider);
  final list = await client.getList('/api/coupons/owner/', null, session.token);
  return list.map((e) => CouponItem.fromJson(e as Map<String, dynamic>)).toList();
});

final chatSessionsProvider = FutureProvider<List<ChatSessionItem>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return [];
  }
  final rows = await ref.watch(apiClientProvider).getList('/api/chat/sessions/', null, session.token);
  return rows.map((row) => ChatSessionItem.fromJson(row as Map<String, dynamic>)).toList();
});
