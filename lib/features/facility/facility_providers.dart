import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/network/api_client.dart';
import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';

class FetchResult<T> {
  const FetchResult({
    required this.data,
    required this.durationMs,
    this.hasNext = false,
  });

  final T data;
  final int durationMs;
  final bool hasNext;
}

String serializeQuery(Map<String, String> query) {
  if (query.isEmpty) {
    return '';
  }
  final keys = query.keys.toList()..sort();
  final normalized = <String, String>{
    for (final key in keys) key: query[key] ?? '',
  };
  return Uri(queryParameters: normalized).query;
}

Map<String, String> deserializeQuery(String queryKey) {
  if (queryKey.trim().isEmpty) {
    return const {};
  }
  return Uri.splitQueryString(queryKey);
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final facilityListProvider = FutureProvider<List<Facility>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final list = await client.getList('/api/facilities/', {'page_size': '40'});
  return list.map((e) => Facility.fromJson(e as Map<String, dynamic>)).toList();
});

final ownerFacilitiesProvider = FutureProvider<List<Facility>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return [];
  }

  final client = ref.watch(apiClientProvider);
  final list = await client.getList(
    '/api/facilities/owner/',
    null,
    session.token,
  );
  return list.map((e) => Facility.fromJson(e as Map<String, dynamic>)).toList();
});

final facilityListByQueryProvider =
    FutureProvider.family<List<Facility>, String>((ref, queryKey) async {
      final client = ref.watch(apiClientProvider);
      final query = deserializeQuery(queryKey);
      final list = await client.getList('/api/facilities/', query);
      return list
          .map((e) => Facility.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final facilityListByQueryWithDiagnosticsProvider =
    FutureProvider.family<FetchResult<List<Facility>>, String>((
      ref,
      queryKey,
    ) async {
      final client = ref.watch(apiClientProvider);
      final query = deserializeQuery(queryKey);
      final stopwatch = Stopwatch()..start();
      final list = await client.getList('/api/facilities/', query);
      stopwatch.stop();
      return FetchResult(
        data: list
            .map((e) => Facility.fromJson(e as Map<String, dynamic>))
            .toList(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    });

final timeSlotListProvider =
    FutureProvider.family<List<TimeSlotItem>, Map<String, String>>((
      ref,
      query,
    ) async {
      final client = ref.watch(apiClientProvider);
      final list = await client.getList('/api/slots/', query);
      return list
          .map((e) => TimeSlotItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return const DashboardSummary(
      confirmedCount: 0,
      pendingCount: 0,
      totalSpent: 0,
      sportAvailability: [],
      upcomingSlots: [],
    );
  }

  final client = ref.watch(apiClientProvider);
  final data = await client.getMap(
    '/api/dashboard/summary/',
    token: session.token,
  );
  return DashboardSummary.fromJson(data);
});

final ownerAnalyticsProvider = FutureProvider<OwnerAnalytics>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) {
    return const OwnerAnalytics(
      totalBookings: 0,
      confirmedBookings: 0,
      pendingBookings: 0,
      cancelledBookings: 0,
      revenue: 0,
      refunds: 0,
      netRevenue: 0,
      cancellationRate: 0,
    );
  }
  final data = await ref
      .watch(apiClientProvider)
      .getMap('/api/owner/analytics/', token: session.token);
  return OwnerAnalytics.fromJson(data);
});

final liveSlotAvailabilityProvider = FutureProvider.autoDispose
    .family<List<LiveSlotAvailability>, String>((ref, queryKey) async {
      final client = ref.watch(apiClientProvider);
      final session = ref.watch(authSessionProvider);
      final query = deserializeQuery(queryKey);
      final page = await client.getPage(
        '/api/live-slots/',
        query: query,
        token: session?.token,
      );
      final list = page['results'] as List<dynamic>;
      return list
          .map((e) => LiveSlotAvailability.fromJson(e as Map<String, dynamic>))
          .toList();
    });

final liveSlotAvailabilityWithDiagnosticsProvider = FutureProvider.autoDispose
    .family<FetchResult<List<LiveSlotAvailability>>, String>((
      ref,
      queryKey,
    ) async {
      final client = ref.watch(apiClientProvider);
      final session = ref.watch(authSessionProvider);
      final query = deserializeQuery(queryKey);
      final stopwatch = Stopwatch()..start();
      final page = await client.getPage(
        '/api/live-slots/',
        query: query,
        token: session?.token,
      );
      stopwatch.stop();
      final list = page['results'] as List<dynamic>;
      return FetchResult(
        data: list
            .map(
              (e) => LiveSlotAvailability.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        durationMs: stopwatch.elapsedMilliseconds,
        hasNext: page['has_next'] == true,
      );
    });
