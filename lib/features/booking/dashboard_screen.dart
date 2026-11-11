import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../../shared/ui/app_theme.dart';
import '../../shared/ui/motion.dart';
import '../../shared/ui/sport_visuals.dart';
import 'booking_providers.dart';
import '../facility/favorite_facility_provider.dart';
import '../facility/facility_providers.dart';
import '../facility/venue_detail_screen.dart';

final dashboardProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return null;

  return ref.watch(apiClientProvider).getMap(
    '/api/auth/profile/',
    token: session.token,
  );
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenQuickBook,
    required this.onOpenExplore,
    required this.onOpenHistory,
    required this.onBookFacility,
  });

  final ValueChanged<List<LiveSlotAvailability>?> onOpenQuickBook;
  final VoidCallback onOpenExplore;
  final VoidCallback onOpenHistory;
  final ValueChanged<Facility> onBookFacility;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const List<String> _sports = [
    'all',
    'football',
    'billiard',
    'pickleball',
    'volleyball',
    'basketball',
    'futsal',
    'tennis',
    'badminton',
  ];

  String _activeSport = 'all';
  String _searchText = '';

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'GOOD MORNING';
    }
    if (hour < 18) {
      return 'GOOD AFTERNOON';
    }
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = textScale > 1.2;
    final compact = width < 430;
    final tablet = width >= 768;
    final horizontalPadding = width >= 1100 ? (width - 1000) / 2 : 20.0;

    final query = {
      'featured': 'true',
      'page_size': '100',
      if (_activeSport != 'all') 'sport_type': _activeSport,
      if (_searchText.isNotEmpty) 'q': _searchText,
    };
    final facilitiesAsync = ref.watch(facilityListByQueryProvider(serializeQuery(query)));
    const allLiveSlotsQuery = '';
    final liveSlotsAsync = ref.watch(liveSlotAvailabilityProvider(allLiveSlotsQuery));
    final activeCouponsAsync = ref.watch(activeCouponsProvider);
    final favoriteIds = ref.watch(favoriteFacilityIdsProvider);
    final profileAsync = ref.watch(dashboardProfileProvider);
    final profile = profileAsync.value;
    final savedDisplayName = (profile?['display_name'] as String?)?.trim() ?? '';
    // Avoid displaying the email-derived username as a profile name.
    // Use a neutral label until the saved profile display name is available.
    final avatarUrl = (profile?['avatar_url'] as String?)?.trim();

    final coupons = activeCouponsAsync.value ?? const <CouponItem>[];
    CouponItem? topCoupon;
    for (final coupon in coupons) {
      if (topCoupon == null || coupon.discountPercent > topCoupon.discountPercent) {
        topCoupon = coupon;
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(facilityListProvider);
        ref.invalidate(liveSlotAvailabilityProvider(allLiveSlotsQuery));
        ref.invalidate(dashboardProfileProvider);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 18, horizontalPadding, 110),
        children: [
          FadeInUp(
            child: _HomeHero(
              wide: tablet,
              onQuickBook: () => widget.onOpenQuickBook(null),
              onExplore: widget.onOpenExplore,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeGreeting(),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      savedDisplayName.isNotEmpty ? savedDisplayName : 'Sports Lover',
                      style: TextStyle(
                        fontSize: tablet ? 40 : (compact ? 30 : 36),
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CircleIconButton(
                icon: Icons.notifications_none_rounded,
                onPressed: () {
                  final messenger = ScaffoldMessenger.of(context);
                  if (topCoupon == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('No active coupon notification right now.')),
                    );
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'New top coupon available: ${topCoupon.code} (${topCoupon.discountPercent.toStringAsFixed(0)}% OFF)',
                      ),
                    ),
                  );
                },
                showDot: topCoupon != null,
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE5E7EB),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                onBackgroundImageError: avatarUrl != null && avatarUrl.isNotEmpty
                    ? (_, _) {}
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? const Icon(Icons.person_rounded, color: Color(0xFF6B7280))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            onChanged: (value) => setState(() => _searchText = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Find a court or club...',
              prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 132,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PromoBannerCard(
                  icon: Icons.local_offer,
                  title: topCoupon == null
                      ? 'Coupon Offers'
                      : '${topCoupon.discountPercent.toStringAsFixed(0)}% OFF • ${topCoupon.code}',
                  subtitle: topCoupon == null
                      ? 'Owner coupons appear here once published'
                      : 'Use coupon code at checkout to apply this discount',
                  colors: const [Color(0xFF065F46), Color(0xFF10B981)],
                ),
                SizedBox(width: 10),
                const _PromoBannerCard(
                  icon: Icons.celebration,
                  title: 'New User 50% OFF',
                  subtitle: 'Limited-time starter reward',
                  colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                ),
                SizedBox(width: 10),
                const _PromoBannerCard(
                  icon: Icons.schedule,
                  title: 'Off-Peak Boost',
                  subtitle: 'Book morning slots for extra savings',
                  colors: [Color(0xFF7C2D12), Color(0xFFF59E0B)],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sports.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final sport = _sports[index];
                final isActive = sport == _activeSport;
                final label = sport == 'all' ? 'All' : _labelForSport(sport);

                return InkWell(
                  onTap: () => setState(() => _activeSport = sport),
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.ink : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isActive ? AppColors.ink : AppColors.border,
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 22),
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          strutStyle: const StrutStyle(height: 1.12, forceStrutHeight: true),
                          style: TextStyle(
                            color: isActive ? AppColors.accent : AppColors.inkSoft,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          if (compact || largeText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Rated Venues',
                  style: TextStyle(fontSize: compact ? 28 : 32, fontWeight: FontWeight.w900, height: 1),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => widget.onOpenQuickBook(null),
                    child: const Text(
                      'Quick Book',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Text(
                  'Top Rated Venues',
                  style: TextStyle(fontSize: compact ? 28 : 36, fontWeight: FontWeight.w900, height: 1),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onOpenQuickBook(null),
                  child: Text(
                    'Quick Book',
                    style: TextStyle(fontSize: compact ? 15 : 18, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          facilitiesAsync.when(
            data: (facilities) {
              final venues = _buildVenues(
                facilities: facilities,
                slots: liveSlotsAsync.asData?.value ?? const [],
                selectedSport: _activeSport,
                searchText: _searchText,
              );

              if (venues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No venues match your filters yet.')),
                );
              }

              final featured = venues.take(4).toList();
              return SizedBox(
                height: 356,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final venue = featured[index];
                    return SizedBox(
                      width: MediaQuery.of(context).size.width.clamp(280, 470).toDouble() - 40,
                      child: FadeInUp(
                        delay: Duration(milliseconds: 80 * index),
                        child: HoverLift(
                        child: _VenueCard(
                        venue: venue,
                        isFavorite: favoriteIds.contains(venue.facility.id),
                        onToggleFavorite: () async {
                          try {
                            await ref.read(favoriteFacilityIdsProvider.notifier).toggle(venue.facility.id);
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(error.toString().replaceFirst('Exception: ', '')),
                              ),
                            );
                          }
                        },
                        onTap: (selected) => _openVenueDetails(
                          context,
                          selected.facility,
                          selected.openHours,
                          selected.rating,
                        ),
                      ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const _DashboardFeaturedSkeleton(),
            error: (error, stack) => SizedBox(
              height: 120,
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(facilityListByQueryProvider(serializeQuery(query))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Unable to load venues. Try Again'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'All Venues',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          facilitiesAsync.when(
            data: (facilities) {
              final venues = _buildVenues(
                facilities: facilities,
                slots: liveSlotsAsync.asData?.value ?? const [],
                selectedSport: _activeSport,
                searchText: _searchText,
              );

              return Column(
                children: venues
                    .map(
                      (venue) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CompactVenueCard(
                          venue: venue,
                          isFavorite: favoriteIds.contains(venue.facility.id),
                          onToggleFavorite: () async {
                            try {
                              await ref.read(favoriteFacilityIdsProvider.notifier).toggle(venue.facility.id);
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                              );
                            }
                          },
                          onTap: (selected) => _openVenueDetails(
                            context,
                            selected.facility,
                            selected.openHours,
                            selected.rating,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const _DashboardExploreSkeleton(),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(facilityListByQueryProvider(serializeQuery(query))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Unable to load Explore. Try Again'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openVenueDetails(
    BuildContext context,
    Facility facility,
    String openHours,
    double rating,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VenueDetailScreen(
          facility: facility,
          openHours: openHours,
          rating: rating,
          onBook: () {
            Navigator.of(context).pop();
            widget.onBookFacility(facility);
          },
        ),
      ),
    );
  }

  List<_VenueView> _buildVenues({
    required List<Facility> facilities,
    required List<LiveSlotAvailability> slots,
    required String selectedSport,
    required String searchText,
  }) {
    final map = <String, _TimeRange>{};
    final bookedCountByFacility = <String, int>{};
    for (final slot in slots) {
      final key = slot.facilityId;
      final current = map[key];
      if (current == null) {
        map[key] = _TimeRange(slot.startAt, slot.endAt);
      } else {
        map[key] = _TimeRange(
          slot.startAt.isBefore(current.openAt) ? slot.startAt : current.openAt,
          slot.endAt.isAfter(current.closeAt) ? slot.endAt : current.closeAt,
        );
      }
      if (slot.bookedByMe) {
        bookedCountByFacility[key] = (bookedCountByFacility[key] ?? 0) + 1;
      }
    }

    return facilities.where((facility) {
      if (selectedSport != 'all' && facility.sportType.toLowerCase() != selectedSport) {
        return false;
      }
      if (searchText.isEmpty) {
        return true;
      }
      return facility.name.toLowerCase().contains(searchText) ||
          facility.locationName.toLowerCase().contains(searchText) ||
          facility.sportType.toLowerCase().contains(searchText);
    }).map((facility) {
      final visual = SportVisuals.ofVenue(
        sportType: facility.sportType,
        venueId: facility.id,
        venueName: facility.name,
      );
      final range = map[facility.id.toString()];
      final openHours = range == null
          ? '08:00-22:00'
          : '${DateFormat('HH:mm').format(range.openAt)}-${DateFormat('HH:mm').format(range.closeAt)}';
      final rating = facility.rating.clamp(0.0, 5.0);

      return _VenueView(
        facility: facility,
        visual: visual,
        openHours: openHours,
        rating: double.parse(rating.toStringAsFixed(1)),
        bookedSlotCount: bookedCountByFacility[facility.id.toString()] ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
  }

  String _labelForSport(String sportType) {
    return SportVisuals.of(sportType).label;
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: IconButton(onPressed: onPressed, icon: Icon(icon, size: 22)),
        ),
        if (showDot)
          Positioned(
            right: 11,
            top: 9,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardFeaturedSkeleton extends StatelessWidget {
  const _DashboardFeaturedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 356,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => Container(
          width: MediaQuery.of(context).size.width.clamp(280, 470).toDouble() - 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemCount: 3,
      ),
    );
  }
}

class _DashboardExploreSkeleton extends StatelessWidget {
  const _DashboardExploreSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 112,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.venue,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final _VenueView venue;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final ValueChanged<_VenueView> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(venue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _AssetOrNetworkImage(
                  networkImageUrl: venue.facility.imageUrl,
                  assetPath: venue.visual.assetPath,
                  fallbackImageUrl: venue.visual.fallbackImageUrl,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                if (venue.hasBookedSlot)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: _PillBadge(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bookmark_added, size: 16, color: Color(0xFF1D4ED8)),
                          const SizedBox(width: 6),
                          Text(
                            venue.bookedSlotCount > 1 ? 'Booked Already (${venue.bookedSlotCount})' : 'Booked Already',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  right: 14,
                  top: 14,
                  child: Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onToggleFavorite,
                          borderRadius: BorderRadius.circular(999),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 1, end: isFavorite ? 1.08 : 1),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) {
                              return Transform.scale(scale: scale, child: child);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: isFavorite
                                    ? const LinearGradient(colors: [Color(0xFF991B1B), Color(0xFFEF4444), Color(0xFFF87171)])
                                    : const LinearGradient(colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB)]),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isFavorite ? const Color(0xFF7F1D1D) : const Color(0xFFD1D5DB),
                                ),
                                boxShadow: isFavorite
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFDC2626).withValues(alpha: 0.34),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: isFavorite ? Colors.white : const Color(0xFF6B7280),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PillBadge(
                        child: venue.rating > 0
                            ? Row(
                                children: [
                                  const Icon(Icons.star, size: 16),
                                  const SizedBox(width: 5),
                                  Text(
                                    venue.rating.toStringAsFixed(1),
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              )
                            : const Text(
                                'New venue',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venue.facility.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF111827), Color(0xFF1F2937)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '\$${venue.facility.basePricePerHour.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 17, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          venue.facility.locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 17, color: Colors.grey.shade500),
                      const SizedBox(width: 5),
                      Text(
                        venue.openHours,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          venue.visual.label.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactVenueCard extends StatelessWidget {
  const _CompactVenueCard({
    required this.venue,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final _VenueView venue;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final ValueChanged<_VenueView> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(venue),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _AssetOrNetworkImage(
                  networkImageUrl: venue.facility.imageUrl,
                  assetPath: venue.visual.assetPath,
                  fallbackImageUrl: venue.visual.fallbackImageUrl,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.facility.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      venue.facility.locationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${venue.openHours} • ${venue.visual.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
                    ),
                    if (venue.hasBookedSlot) ...[
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          venue.bookedSlotCount > 1 ? 'Booked Already (${venue.bookedSlotCount})' : 'Booked Already',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1D4ED8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: isFavorite ? 'Remove saved venue' : 'Save venue',
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorite ? const Color(0xFFE11D48) : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B3B2E), Color(0xFF0F766E)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '\$${venue.facility.basePricePerHour.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _VenueView {
  const _VenueView({
    required this.facility,
    required this.visual,
    required this.openHours,
    required this.rating,
    required this.bookedSlotCount,
  });

  final Facility facility;
  final SportVisual visual;
  final String openHours;
  final double rating;
  final int bookedSlotCount;

  bool get hasBookedSlot => bookedSlotCount > 0;
}

class _TimeRange {
  const _TimeRange(this.openAt, this.closeAt);

  final DateTime openAt;
  final DateTime closeAt;
}

class _AssetOrNetworkImage extends StatelessWidget {
  const _AssetOrNetworkImage({
    required this.assetPath,
    required this.fallbackImageUrl,
    this.networkImageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String assetPath;
  final String fallbackImageUrl;
  final String? networkImageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (networkImageUrl != null && networkImageUrl!.isNotEmpty) {
      return Image.network(
        networkImageUrl!,
        width: width,
        height: height,
        fit: fit,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _fallbackImage(),
      );
    }

    return _fallbackImage();
  }

  Widget _fallbackImage() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          fallbackImageUrl,
          width: width,
          height: height,
          fit: fit,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (context, networkError, networkStack) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Icon(Icons.image_not_supported_outlined),
            );
          },
        );
      },
    );
  }
}


class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.wide, required this.onQuickBook, required this.onExplore});

  final bool wide;
  final VoidCallback onQuickBook;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: wide ? 320 : 250,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/sports/all_sports.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroGradient),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    AppColors.ink.withValues(alpha: 0.92),
                    AppColors.primaryDark.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(wide ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text(
                      'LIVE COURTS TODAY',
                      style: TextStyle(
                        color: AppColors.onAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Book your game.\nPlay tonight.',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: Colors.white,
                          fontSize: wide ? 44 : 30,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onQuickBook,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                        ),
                        icon: const Icon(Icons.bolt_rounded),
                        label: const Text('Quick Book'),
                      ),
                      OutlinedButton(
                        onPressed: onExplore,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        child: const Text('Explore venues'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
