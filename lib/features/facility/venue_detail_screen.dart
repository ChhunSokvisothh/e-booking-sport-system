
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/models.dart';
import '../../shared/ui/sport_visuals.dart';
import '../../shared/ui/app_page_frame.dart';
import 'favorite_facility_provider.dart';

class VenueDetailScreen extends ConsumerWidget {
  const VenueDetailScreen({
    super.key,
    required this.facility,
    required this.openHours,
    required this.rating,
    required this.onBook,
  });

  final Facility facility;
  final String openHours;
  final double rating;
  final VoidCallback onBook;

  static const Color _background = Color(0xFFF4F5F7);
  static const Color _ink = Color(0xFF101218);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _accent = Color(0xFF16835D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIds = ref.watch(favoriteFacilityIdsProvider);
    final isFavorite = favoriteIds.contains(facility.id);
    final visual = SportVisuals.ofVenue(
      sportType: facility.sportType,
      venueId: facility.id,
      venueName: facility.name,
    );

    final isWide = MediaQuery.sizeOf(context).width > 720;

    final galleryImages = <String>[
      if (facility.imageUrl != null &&
          facility.imageUrl!.trim().isNotEmpty)
        facility.imageUrl!.trim(),
      ...facility.galleryImageUrls.where(
        (url) => url.trim().isNotEmpty,
      ),
    ].toSet().toList();

    final displayHours = facility.openingHours.trim().isNotEmpty
        ? facility.openingHours.trim()
        : openHours;

    final hasCoordinates =
        facility.latitude.isFinite &&
        facility.longitude.isFinite &&
        facility.latitude >= -90 &&
        facility.latitude <= 90 &&
        facility.longitude >= -180 &&
        facility.longitude <= 180 &&
        !(facility.latitude == 11.5564 &&
            facility.longitude == 104.9282);

    final detailsCard = _buildDetailsCard(
      context: context,
      visual: visual,
      displayHours: displayHours,
    );

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Venue Details',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Remove from saved venues' : 'Save venue',
            onPressed: () async {
              try {
                await ref
                    .read(favoriteFacilityIdsProvider.notifier)
                    .toggle(facility.id);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              }
            },
            icon: Icon(
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFavorite ? const Color(0xFFE11D48) : _ink,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\$${facility.basePricePerHour.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    const Text(
                      'per hour',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onBook,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Book this venue'),
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(190, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AppPageFrame(
        maxWidth: 1120,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
          _buildGallery(
            context: context,
            images: galleryImages,
            assetPath: visual.assetPath,
            fallbackImageUrl: visual.fallbackImageUrl,
            height: isWide ? 380 : 250,
          ),
          const SizedBox(height: 20),

          if (isWide)
            detailsCard
          else
            detailsCard,

          if (facility.amenities.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionCard(
              title: 'Facilities and amenities',
              subtitle: 'What this venue offers',
              icon: Icons.check_circle_outline_rounded,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: facility.amenities
                    .where((item) => item.trim().isNotEmpty)
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: _accent,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              item,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),
          _sectionCard(
            title: 'Venue information',
            subtitle: 'Useful details before you book',
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                if (facility.surfaceType.trim().isNotEmpty)
                  _infoRow(
                    icon: Icons.sports_soccer_rounded,
                    title: 'Surface',
                    value: facility.surfaceType,
                  ),
                if (facility.courtCount > 0)
                  _infoRow(
                    icon: Icons.stadium_outlined,
                    title: 'Courts / playing areas',
                    value: '${facility.courtCount}',
                  ),
                _infoRow(
                  icon: Icons.access_time_rounded,
                  title: 'Opening hours',
                  value: displayHours,
                ),
                if (facility.cancellationPolicy.trim().isNotEmpty)
                  _infoRow(
                    icon: Icons.event_busy_outlined,
                    title: 'Cancellation policy',
                    value: facility.cancellationPolicy,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionCard(
            title: 'Location',
            subtitle: facility.locationName,
            icon: Icons.location_on_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasCoordinates)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(
                                facility.latitude,
                                facility.longitude,
                              ),
                              initialZoom: 15,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.ebookingsport.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      facility.latitude,
                                      facility.longitude,
                                    ),
                                    width: 44,
                                    height: 44,
                                    child: const Icon(
                                      Icons.location_pin,
                                      size: 42,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ],
                              ),
                              RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    'OpenStreetMap contributors',
                                    onTap: () => launchUrl(
                                      Uri.parse(
                                        'https://www.openstreetmap.org/copyright',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.location_off_outlined,
                          color: _muted,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'The venue location has not been configured yet.',
                            style: TextStyle(
                              color: _muted,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: _muted,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        facility.locationName,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard({
    required BuildContext context,
    required dynamic visual,
    required String displayHours,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(label: visual.label.toUpperCase()),
              _TagChip(
                label: facility.isIndoor ? 'INDOOR' : 'OUTDOOR',
              ),
              const _TagChip(label: 'VENUE'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            facility.name,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.12,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: _muted,
                size: 20,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  facility.locationName,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFE6A700),
                    size: 21,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'rating',
                    style: TextStyle(color: _muted),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: _muted,
                    size: 19,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    displayHours,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          const Text(
            'About this venue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            facility.description.trim().isEmpty
                ? 'Venue information has not been provided yet. Contact the venue for more details before booking.'
                : facility.description.trim(),
            style: const TextStyle(
              color: _muted,
              height: 1.6,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Price',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '\$${facility.basePricePerHour.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    const Text(
                      'per hour',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.verified_outlined,
                color: _accent,
                size: 20,
              ),
              const SizedBox(width: 6),
              const Text(
                'Booking available',
                style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGallery({
    required BuildContext context,
    required List<String> images,
    required String assetPath,
    required String fallbackImageUrl,
    required double height,
  }) {
    return _AutoRotatingGallery(
      images: images,
      assetPath: assetPath,
      fallbackImageUrl: fallbackImageUrl,
      height: height,
    );
  }

  // // Used by the gallery callback; set by the gallery builder below.
  // BuildContext get _galleryContext => _currentGalleryContext!;

  // BuildContext? _currentGalleryContext;

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: _ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _muted, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 125,
            child: Text(
              title,
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _AutoRotatingGallery extends StatefulWidget {
  const _AutoRotatingGallery({
    required this.images,
    required this.assetPath,
    required this.fallbackImageUrl,
    required this.height,
  });

  final List<String> images;
  final String assetPath;
  final String fallbackImageUrl;
  final double height;

  @override
  State<_AutoRotatingGallery> createState() => _AutoRotatingGalleryState();
}

class _AutoRotatingGalleryState extends State<_AutoRotatingGallery> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.images.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _touching || !_controller.hasClients) return;
      final next = (_index + 1) % widget.images.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: _AssetOrNetworkImage(
          assetPath: widget.assetPath,
          fallbackImageUrl: widget.fallbackImageUrl,
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: (_) => _touching = true,
              onPointerUp: (_) {
                _touching = false;
                _startTimer();
              },
              onPointerCancel: (_) {
                _touching = false;
                _startTimer();
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => _AssetOrNetworkImage(
                  networkImageUrl: widget.images[index],
                  assetPath: widget.assetPath,
                  fallbackImageUrl: widget.fallbackImageUrl,
                  height: widget.height,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (widget.images.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (index) {
                    final selected = index == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.white70,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
            if (widget.images.length > 1)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({
    required this.images,
    required this.initialIndex,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_index + 1} of ${widget.images.length} photos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (index) {
                  setState(() => _index = index);
                },
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        widget.images[index],
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7280),
          fontSize: 11,
          letterSpacing: 0.3,
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
    if (networkImageUrl != null &&
        networkImageUrl!.trim().isNotEmpty) {
      return Image.network(
        networkImageUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        return Image.network(
          fallbackImageUrl,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) {
            return Container(
              width: width,
              height: height,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                size: 36,
                color: Colors.grey,
              ),
            );
          },
        );
      },
    );
  }
}
