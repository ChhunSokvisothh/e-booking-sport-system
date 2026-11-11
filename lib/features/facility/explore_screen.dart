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

              final cards = saved.map((facility) {
                  final visual = SportVisuals.ofVenue(
                    sportType: facility.sportType,
                    venueId: facility.id,
                    venueName: facility.name,
                  );
                  return Material(
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
                                // Fixed 16:9 frame so photos are cropped, never stretched.
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: _AssetOrNetworkImage(
                                    assetPath: visual.assetPath,
                                    fallbackImageUrl: visual.fallbackImageUrl,
                                    networkImageUrl: facility.imageUrl,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
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
                                      if (facility.rating > 0) ...[
                                        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                                        const SizedBox(width: 4),
                                        Text(facility.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                                      ] else
                                        const Text('New · Not rated', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                      const Spacer(),
                                      Text(
                                        '\$${facility.basePricePerHour.toStringAsFixed(0)}/hr',
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
                  );
                }).toList();

              // Phone: one card per row. Wider screens (web/tablet): two columns.
              return LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 16.0;
                  final maxWidth = constraints.maxWidth.clamp(0.0, 1100.0);
                  final columns = maxWidth >= 720 ? 2 : 1;
                  final itemWidth = (maxWidth - gap * (columns - 1)) / columns;
                  return Center(
                    child: SizedBox(
                      width: maxWidth,
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final card in cards) SizedBox(width: itemWidth, child: card),
                        ],
                      ),
                    ),
                  );
                },
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
            color: const Color(0xFFF5F7F2),
            borderRadius: BorderRadius.circular(20),
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
