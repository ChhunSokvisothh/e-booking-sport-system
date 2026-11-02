import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/network/api_client.dart';
import '../auth/data/auth_session.dart';
import 'facility_providers.dart';

class FavoriteFacilityController extends StateNotifier<Set<int>> {
  FavoriteFacilityController(this._ref) : super(<int>{}) {
    _ref.listen<AuthSession?>(authSessionProvider, (previous, next) {
      _load(next);
    });
    _load(_ref.read(authSessionProvider));
  }

  final Ref _ref;
  int _loadGeneration = 0;

  Future<void> _load(AuthSession? session) async {
    final generation = ++_loadGeneration;
    if (session == null) {
      state = <int>{};
      return;
    }

    try {
      final response = await _ref.read(apiClientProvider).getMap(
        '/api/favorites/',
        token: session.token,
      );
      if (generation != _loadGeneration) return;
      final ids = (response['facility_ids'] as List<dynamic>? ?? const [])
          .map((value) => int.tryParse(value.toString()))
          .whereType<int>()
          .toSet();
      state = ids;
    } catch (_) {
      // Preserve the current state if a transient refresh fails.
    }
  }

  Future<void> toggle(int facilityId) async {
    final session = _ref.read(authSessionProvider);
    if (session == null) {
      throw Exception('Sign in to save venues to your account.');
    }

    final wasFavorite = state.contains(facilityId);
    final next = Set<int>.from(state);
    if (wasFavorite) {
      next.remove(facilityId);
    } else {
      next.add(facilityId);
    }
    state = next;

    try {
      final client = _ref.read(apiClientProvider);
      if (wasFavorite) {
        await client.deleteJson(
          '/api/favorites/$facilityId/',
          token: session.token,
        );
      } else {
        await client.postJson(
          '/api/favorites/',
          {'facility_id': facilityId},
          token: session.token,
        );
      }
    } catch (_) {
      state = Set<int>.from(state)
        ..remove(facilityId)
        ..addAll(wasFavorite ? <int>{facilityId} : <int>{});
      rethrow;
    }
  }
}

final favoriteFacilityIdsProvider =
    StateNotifierProvider<FavoriteFacilityController, Set<int>>((ref) {
  return FavoriteFacilityController(ref);
});
