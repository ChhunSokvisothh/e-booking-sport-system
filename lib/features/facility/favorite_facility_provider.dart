import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _favoriteFacilitiesKey = 'favorite_facility_ids_v1';

class FavoriteFacilityController extends StateNotifier<Set<int>> {
  FavoriteFacilityController() : super(<int>{}) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoriteFacilitiesKey) ?? const [];
    final parsed = raw.map(int.tryParse).whereType<int>().toSet();
    state = parsed;
  }

  Future<void> toggle(int facilityId) async {
    final next = Set<int>.from(state);
    if (next.contains(facilityId)) {
      next.remove(facilityId);
    } else {
      next.add(facilityId);
    }

    state = next;

    final prefs = await SharedPreferences.getInstance();
    final encoded = next.map((e) => e.toString()).toList();
    await prefs.setStringList(_favoriteFacilitiesKey, encoded);
  }

  bool isFavorite(int facilityId) => state.contains(facilityId);
}

final favoriteFacilityIdsProvider =
    StateNotifierProvider<FavoriteFacilityController, Set<int>>((ref) {
      return FavoriteFacilityController();
    });
