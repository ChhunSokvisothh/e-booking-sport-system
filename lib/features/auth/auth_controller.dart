import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_session.dart';
import '../booking/booking_providers.dart';
import '../facility/facility_providers.dart';

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});

class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  void _invalidateSessionScopedProviders() {
    _ref.invalidate(bookingHistoryProvider);
    _ref.invalidate(dashboardSummaryProvider);
    _ref.invalidate(activeCouponsProvider);
    _ref.invalidate(ownerCouponsProvider);
    _ref.invalidate(chatSessionsProvider);
    _ref.invalidate(facilityListProvider);
    _ref.invalidate(facilityListByQueryProvider);
    _ref.invalidate(facilityListByQueryWithDiagnosticsProvider);
    _ref.invalidate(ownerFacilitiesProvider);
    _ref.invalidate(liveSlotAvailabilityProvider);
    _ref.invalidate(liveSlotAvailabilityWithDiagnosticsProvider);
  }

  Future<void> refreshSession() async {
    final current = _ref.read(authSessionProvider);
    if (current == null) {
      return;
    }

    final api = _ref.read(apiClientProvider);
    final result = await api.getMap('/api/auth/me/', token: current.token);
    final updated = AuthSession(
      token: current.token,
      userId: result['user_id'] as int,
      userUuid: result['user_uuid'] as String,
      email: result['email'] as String,
      role: (result['role'] as String?) ?? current.role,
      ownerStatus: result['owner_status'] as String? ?? current.ownerStatus,
    );
    _ref.read(authSessionProvider.notifier).state = updated;
    await persistAuthSession(updated);
    _invalidateSessionScopedProviders();
  }

  Future<void> signUp({required String email, required String password}) async {
    final api = _ref.read(apiClientProvider);
    final result = await api.postJson('/api/auth/signup/', {
      'email': email,
      'password': password,
    });
    await _saveSessionFromAuthResponse(result);
  }

  Future<void> ownerSignUp({
    required String email,
    required String password,
    required String venueName,
    required String contactPhone,
  }) async {
    final result = await _ref
        .read(apiClientProvider)
        .postJson('/api/auth/owner-signup/', {
          'email': email,
          'password': password,
          'venue_name': venueName,
          'contact_phone': contactPhone,
        });
    await _saveSessionFromAuthResponse(result);
  }

  Future<void> login({required String email, required String password}) async {
    final api = _ref.read(apiClientProvider);
    final result = await api.postJson('/api/auth/login/', {
      'email': email,
      'password': password,
    });
    await _saveSessionFromAuthResponse(result);
  }

  Future<void> logout() async {
    final current = _ref.read(authSessionProvider);
    if (current != null) {
      final api = _ref.read(apiClientProvider);
      try {
        await api.postJson('/api/auth/logout/', {}, token: current.token);
      } catch (_) {
        // Local logout should still proceed even if server token is already invalid.
      }
    }

    _ref.read(authSessionProvider.notifier).state = null;
    _invalidateSessionScopedProviders();
    await clearStoredAuthSession();
  }

  Future<void> _saveSessionFromAuthResponse(Map<String, dynamic> json) async {
    final session = AuthSession(
      token: json['token'] as String,
      userId: json['user_id'] as int,
      userUuid: json['user_uuid'] as String,
      email: json['email'] as String,
      role: (json['role'] as String?) ?? 'user',
      ownerStatus: json['owner_status'] as String?,
    );
    _ref.read(authSessionProvider.notifier).state = session;
    await persistAuthSession(session);
    _invalidateSessionScopedProviders();
  }
}
