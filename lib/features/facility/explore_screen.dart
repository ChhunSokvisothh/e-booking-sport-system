import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_transitions.dart';
import '../../core/models.dart';
import '../../core/sport_visuals.dart';
import '../booking/quick_book_screen.dart';
import 'facility_providers.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({
    super.key,
    required this.onOpenDashboard,
  });

  final VoidCallback onOpenDashboard;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  static const int _pageSize = 12;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String? _sportType;
  bool _indoorOnly = false;
  int _page = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> _query() {
    return {
      'featured': 'true',
      'page': _page.toString(),
      'page_size': '$_pageSize',
      if (_searchText.isNotEmpty) 'q': _searchText,
      ...?_sportType == null ? null : {'sport_type': _sportType!},
      if (_indoorOnly) 'is_indoor': 'true',
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = textScale > 1.2;
    final compact = width < 430;
    final tablet = width >= 768;
    final horizontalPadding = width >= 1100 ? (width - 1000) / 2 : 16.0;

    final query = _query();
    final queryKey = serializeQuery(query);
    final facilitiesAsync = ref.watch(facilityListByQueryWithDiagnosticsProvider(queryKey));
    const allLiveSlotsQuery = '';
    final liveSlotsAsync = ref.watch(liveSlotAvailabilityProvider(allLiveSlotsQuery));
    final bookedCountByFacility = <String, int>{};
    for (final row in (liveSlotsAsync.asData?.value ?? const <LiveSlotAvailability>[])) {
      if (!row.bookedByMe) {
        continue;
      }
      bookedCountByFacility[row.facilityId] = (bookedCountByFacility[row.facilityId] ?? 0) + 1;
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 100),
      children: [
        Text(
          'Explore Venues',
          style: TextStyle(
            fontSize: largeText ? (compact ? 24 : 30) : (tablet ? 36 : (compact ? 28 : 34)),
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Server-ranked by relevance and rating.',
          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  final normalized = value.toLowerCase();
                  if (value != normalized) {
                    _searchController.value = TextEditingValue(
                      text: normalized,
                      selection: TextSelection.collapsed(offset: normalized.length),
                    );
                  }
                  setState(() {
                    _searchText = normalized.trim();
                    _page = 1;
                  });
                },
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'Search name or location',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(buildSlideFadeRoute(QuickBookScreen(onOpenDashboard: widget.onOpenDashboard)));
              },
              icon: const Icon(Icons.flash_on),
              label: const Text('Quick'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: SportVisuals.all.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _FilterChip(
                  label: 'All',
                  selected: _sportType == null,
                  onTap: () {
                    setState(() {
                      _sportType = null;
                      _page = 1;
                    });
                  },
                );
              }

              final visual = SportVisuals.all[index - 1];
              final selected = _sportType == visual.sportType;
              return _FilterChip(
                label: visual.label,
                selected: selected,
                onTap: () {
                  setState(() {
                    _sportType = visual.sportType;
                    _page = 1;
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: _indoorOnly,
              onChanged: (value) {
                setState(() {
                  _indoorOnly = value ?? false;
                  _page = 1;
                });
              },
            ),
            const Text('Indoor only', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchText = '';
                  _sportType = null;
                  _indoorOnly = false;
                  _page = 1;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reset filters'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Discover By Sport',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SportVisuals.all.take(5).map((visual) {
                  return ActionChip(
                    backgroundColor: Colors.white,
                    label: Text(visual.label),
                    avatar: Icon(visual.icon, size: 18),
                    onPressed: () {
                      setState(() {
                        _sportType = visual.sportType;
                        _page = 1;
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        facilitiesAsync.when(
          data: (payload) {
            final facilities = payload.data;
            if (facilities.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No venues found on this page.', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Try another sport filter or open Quick Booking to browse live available slots instantly.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(buildSlideFadeRoute(QuickBookScreen(onOpenDashboard: widget.onOpenDashboard)));
                      },
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Open Quick Booking'),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                ...facilities.map((facility) {
                  final visual = SportVisuals.ofVenue(
                    sportType: facility.sportType,
                    venueId: facility.id,
                    venueName: facility.name,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ExploreCard(
                      facility: facility,
                      visual: visual,
                      bookedSlotCount: bookedCountByFacility[facility.id.toString()] ?? 0,
                      onTap: () {
                        final matchingSlots = (liveSlotsAsync.asData?.value ?? const <LiveSlotAvailability>[])
                            .where((slot) => slot.facilityId == facility.id.toString())
                            .toList()
                          ..sort((a, b) => a.startAt.compareTo(b.startAt));
                        Navigator.of(context).push(
                          buildSlideFadeRoute(
                            QuickBookScreen(
                              onOpenDashboard: widget.onOpenDashboard,
                              initialSportType: facility.sportType,
                              initialFacilityId: facility.id.toString(),
                              initialSlots: matchingSlots.isEmpty ? null : matchingSlots,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _page > 1
                            ? () {
                                setState(() => _page -= 1);
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Page $_page', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: facilities.length >= _pageSize
                            ? () {
                                setState(() => _page += 1);
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
          loading: () => const _ExploreSkeletonList(),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load venues right now.'),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(facilityListByQueryWithDiagnosticsProvider(queryKey)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
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
