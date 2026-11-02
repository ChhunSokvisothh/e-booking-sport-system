import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/app_transitions.dart';
import '../../shared/models/models.dart';
import '../auth/data/auth_session.dart';
import '../../shared/ui/sport_visuals.dart';
import '../booking/quick_book_screen.dart';
import 'facility_providers.dart';
import 'favorite_facility_provider.dart';
import 'venue_detail_screen.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({
    super.key,
    required this.onOpenDashboard,
  });

  final VoidCallback onOpenDashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final favoriteIds = ref.watch(favoriteFacilityIdsProvider);
    final facilitiesAsync = ref.watch(facilityListProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      children: [
        const Text(
          'Saved Venues',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Your shortlist, ready whenever you want to play.',
          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        if (session == null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 30),
                SizedBox(height: 10),
                Text('Sign in to sync saved venues', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                SizedBox(height: 6),
                Text('Saved venues are linked to your account so they can follow you across devices. Open Profile to sign in.'),
              ],
            ),
          )
        else
          facilitiesAsync.when(
            loading: () => const _ExploreSkeletonList(),
            error: (error, stack) => Column(
              children: [
                const Text('Could not load your saved venues.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(facilityListProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
            data: (facilities) {
              final saved = facilities.where((facility) => favoriteIds.contains(facility.id)).toList();
              if (saved.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.favorite_border_rounded, size: 42, color: Color(0xFF6B7280)),
                      SizedBox(height: 10),
                      Text('No saved venues yet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      SizedBox(height: 6),
                      Text(
                        'Open Home, choose a venue you like, and tap the heart to add it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: saved.map((facility) {
                  final visual = SportVisuals.ofVenue(
                    sportType: facility.sportType,
                    venueId: facility.id,
                    venueName: facility.name,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          buildSlideFadeRoute(
                            VenueDetailScreen(
                              facility: facility,
                              openHours: facility.openingHours.isNotEmpty
                                  ? facility.openingHours
                                  : 'Contact venue for opening hours',
                              rating: facility.rating,
                              onBook: () => Navigator.of(context).push(
                                buildSlideFadeRoute(
                                  QuickBookScreen(
                                    onOpenDashboard: onOpenDashboard,
                                    initialSportType: facility.sportType,
                                    initialFacilityId: facility.id.toString(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                _AssetOrNetworkImage(
                                  assetPath: visual.assetPath,
                                  fallbackImageUrl: visual.fallbackImageUrl,
                                  networkImageUrl: facility.imageUrl,
                                  height: 170,
                                  width: double.infinity,
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Material(
                                    color: Colors.white,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Remove from saved venues',
                                      onPressed: () async {
                                        try {
                                          await ref.read(favoriteFacilityIdsProvider.notifier).toggle(facility.id);
                                        } catch (error) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.favorite_rounded, color: Color(0xFFE11D48)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(facility.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${facility.locationName} • ${visual.label}',
                                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                                      const SizedBox(width: 4),
                                      Text(facility.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                                      const Spacer(),
                                      Text(
                                        '\${facility.basePricePerHour.toStringAsFixed(0)}/hr',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => Navigator.of(context).push(
                                        buildSlideFadeRoute(
                                          VenueDetailScreen(
                                            facility: facility,
                                            openHours: facility.openingHours.isNotEmpty
                                                ? facility.openingHours
                                                : 'Contact venue for opening hours',
                                            rating: facility.rating,
                                            onBook: () => Navigator.of(context).push(
                                              buildSlideFadeRoute(
                                                QuickBookScreen(
                                                  onOpenDashboard: onOpenDashboard,
                                                  initialSportType: facility.sportType,
                                                  initialFacilityId: facility.id.toString(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(Icons.arrow_forward_rounded),
                                      label: const Text('View venue'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}

class _ExploreSkeletonList extends StatelessWidget {
  const _ExploreSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 212,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF111318) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? const Color(0xFF111318) : const Color(0xFFE5E7EB)),
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
                  color: selected ? Colors.white : const Color(0xFF4B5563),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.facility,
    required this.visual,
    required this.bookedSlotCount,
    required this.onTap,
  });

  final Facility facility;
  final SportVisual visual;
  final int bookedSlotCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = visual.gradient.last;
    return Semantics(
      container: true,
      button: true,
      label: '${facility.name}, ${visual.label}, rated ${facility.rating.toStringAsFixed(1)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: 1.5,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _AssetOrNetworkImage(
                    assetPath: visual.assetPath,
                    fallbackImageUrl: visual.fallbackImageUrl,
                    networkImageUrl: facility.imageUrl,
                    height: 142,
                    width: double.infinity,
                  ),
                  if (bookedSlotCount > 0)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bookmark_added, size: 14, color: Color(0xFF1D4ED8)),
                            const SizedBox(width: 5),
                            Text(
                              bookedSlotCount > 1 ? 'Booked Already ($bookedSlotCount)' : 'Booked Already',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1D4ED8),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            facility.rating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 340;
                    final priceChip = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.92),
                            visual.gradient.first.withValues(alpha: 0.92),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${facility.basePricePerHour.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '/hour',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );

                    final infoColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          facility.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${visual.label} • ${facility.locationName}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.18,
                          ),
                        ),
                      ],
                    );

                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          infoColumn,
                          const SizedBox(height: 10),
                          Align(alignment: Alignment.centerRight, child: priceChip),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: infoColumn),
                        const SizedBox(width: 10),
                        priceChip,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetOrNetworkImage extends StatelessWidget {
  const _AssetOrNetworkImage({
    required this.assetPath,
    required this.fallbackImageUrl,
    this.networkImageUrl,
    this.width,
    this.height,
  });

  final String assetPath;
  final String fallbackImageUrl;
  final String? networkImageUrl;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (networkImageUrl != null && networkImageUrl!.isNotEmpty) {
      return Image.network(
        networkImageUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          fallbackImageUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
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
