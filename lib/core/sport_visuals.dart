import 'package:flutter/material.dart';

class SportVisual {
  const SportVisual({
    required this.sportType,
    required this.label,
    required this.icon,
    required this.assetPath,
    required this.fallbackImageUrl,
    required this.gradient,
  });

  final String sportType;
  final String label;
  final IconData icon;
  final String assetPath;
  final String fallbackImageUrl;
  final List<Color> gradient;

  SportVisual copyWith({
    String? assetPath,
  }) {
    return SportVisual(
      sportType: sportType,
      label: label,
      icon: icon,
      assetPath: assetPath ?? this.assetPath,
      fallbackImageUrl: fallbackImageUrl,
      gradient: gradient,
    );
  }
}

class SportVisuals {
  static const SportVisual _fallback = SportVisual(
    sportType: 'all',
    label: 'All Sports',
    icon: Icons.sports,
    assetPath: 'assets/images/sports/all_sports.jpg',
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1521412644187-c49fa049e84d?auto=format&fit=crop&w=1200&q=80',
    gradient: [Color(0xFF0F766E), Color(0xFF0891B2)],
  );

  static const List<SportVisual> all = [
    SportVisual(
      sportType: 'football',
      label: 'Football',
      icon: Icons.sports_soccer,
      assetPath: 'assets/images/sports/football.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1518091043644-c1d4457512c6?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF047857), Color(0xFF10B981)],
    ),
    SportVisual(
      sportType: 'billiard',
      label: 'Billiard',
      icon: Icons.sports_bar,
      assetPath: 'assets/images/sports/billiard.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1612874742237-6526221588e3?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
    ),
    SportVisual(
      sportType: 'pickleball',
      label: 'Pickleball',
      icon: Icons.sports_tennis,
      assetPath: 'assets/images/sports/pickleball.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1534158914592-062992fbe900?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF7C2D12), Color(0xFFF97316)],
    ),
    SportVisual(
      sportType: 'volleyball',
      label: 'Volleyball',
      icon: Icons.sports_volleyball,
      assetPath: 'assets/images/sports/volleyball.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
    ),
    SportVisual(
      sportType: 'basketball',
      label: 'Basketball',
      icon: Icons.sports_basketball,
      assetPath: 'assets/images/sports/basketball.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1546519638-68e109498ffc?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFFB45309), Color(0xFFF59E0B)],
    ),
    SportVisual(
      sportType: 'futsal',
      label: 'Futsal',
      icon: Icons.sports_soccer,
      assetPath: 'assets/images/sports/futsal.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1579952363873-27f3bade9f55?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF0F766E), Color(0xFF06B6D4)],
    ),
    SportVisual(
      sportType: 'tennis',
      label: 'Tennis',
      icon: Icons.sports_tennis,
      assetPath: 'assets/images/sports/tennis.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1622279457486-28f9c6f3f70e?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF166534), Color(0xFF22C55E)],
    ),
    SportVisual(
      sportType: 'badminton',
      label: 'Badminton',
      icon: Icons.sports,
      assetPath: 'assets/images/sports/badminton.jpg',
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?auto=format&fit=crop&w=1200&q=80',
      gradient: [Color(0xFF9D174D), Color(0xFFEC4899)],
    ),
  ];

  static const Map<String, List<String>> _assetVariantsBySport = {
    'football': [
      'assets/images/sports/football1.png',
      'assets/images/sports/football2.png',
      'assets/images/sports/football3.png',
      'assets/images/sports/football4.png',
      'assets/images/sports/football5.png',
    ],
    'billiard': [
      'assets/images/sports/billiard1.png',
      'assets/images/sports/billiard2.png',
      'assets/images/sports/billiard3.png',
      'assets/images/sports/billiard4.png',
      'assets/images/sports/billiard5.png',
    ],
    'pickleball': [
      'assets/images/sports/pickleball1.png',
      'assets/images/sports/pickleball2.png',
      'assets/images/sports/pickleball3.png',
      'assets/images/sports/pickleball4.png',
      'assets/images/sports/pickleball5.png',
    ],
    'volleyball': [
      'assets/images/sports/volleyball1.png',
      'assets/images/sports/volleyball2.png',
      'assets/images/sports/volleyball3.png',
      'assets/images/sports/volleyball4.png',
      'assets/images/sports/volleyball5.png',
    ],
    'basketball': [
      'assets/images/sports/basketball1.png',
      'assets/images/sports/basketball2.png',
      'assets/images/sports/basketball3.png',
      'assets/images/sports/basketball4.png',
      'assets/images/sports/basketball5.png',
    ],
    'futsal': [
      'assets/images/sports/futsal1.png',
      'assets/images/sports/futsal2.png',
      'assets/images/sports/futsal3.png',
      'assets/images/sports/futsal4.png',
      'assets/images/sports/futsal5.png',
    ],
    'tennis': [
      'assets/images/sports/tennis1.png',
      'assets/images/sports/tennis2.png',
      'assets/images/sports/tennis3.png',
      'assets/images/sports/tennis4.png',
      'assets/images/sports/tennis5.png',
    ],
    'badminton': [
      'assets/images/sports/badminton1.png',
      'assets/images/sports/badminton2.png',
      'assets/images/sports/badminton3.png',
      'assets/images/sports/badminton4.png',
      'assets/images/sports/badminton5.png',
    ],
  };

  static SportVisual of(String? sportType) {
    if (sportType == null || sportType.isEmpty) {
      return _fallback;
    }
    return all.firstWhere(
      (item) => item.sportType == sportType.toLowerCase(),
      orElse: () => _fallback,
    );
  }

  static SportVisual ofVenue({
    required String? sportType,
    required int venueId,
    String? venueName,
  }) {
    final base = of(sportType);
    final normalizedSport = base.sportType.toLowerCase();
    final variants = _assetVariantsBySport[normalizedSport];
    if (variants == null || variants.isEmpty) {
      return base;
    }

    final seed = '$normalizedSport|$venueId|${venueName ?? ''}';
    final index = seed.hashCode.abs() % variants.length;
    return base.copyWith(assetPath: variants[index]);
  }
}
