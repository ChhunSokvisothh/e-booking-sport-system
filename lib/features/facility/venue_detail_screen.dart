import 'package:flutter/material.dart';

import '../../shared/models/models.dart';
import '../../shared/ui/sport_visuals.dart';

class VenueDetailScreen extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final visual = SportVisuals.ofVenue(
      sportType: facility.sportType,
      venueId: facility.id,
      venueName: facility.name,
    );
    final isWide = MediaQuery.of(context).size.width > 720;

    final infoCard = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  facility.name,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, height: 1.05),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '\$${facility.basePricePerHour.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  facility.locationName,
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(openHours, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Icon(Icons.star, color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 4),
              Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(label: visual.label.toUpperCase()),
              _TagChip(label: facility.isIndoor ? 'INDOOR' : 'OUTDOOR'),
              _TagChip(label: 'LIVE AVAILABLE'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            facility.description.trim().isEmpty
                ? 'A premium venue ready for your next game. Book a slot in seconds and manage everything from one place.'
                : facility.description,
            style: TextStyle(color: Colors.grey.shade700, height: 1.45),
          ),
          if (facility.surfaceType.trim().isNotEmpty || facility.courtCount > 0) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (facility.surfaceType.trim().isNotEmpty)
                  _TagChip(label: facility.surfaceType.toUpperCase()),
                _TagChip(label: '${facility.courtCount} COURT${facility.courtCount == 1 ? '' : 'S'}'),
              ],
            ),
          ],
          if (facility.amenities.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Amenities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: facility.amenities.map((amenity) => _TagChip(label: amenity)).toList(),
            ),
          ],
          if (facility.contactPhone.trim().isNotEmpty || facility.websiteUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Contact', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            if (facility.contactPhone.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Phone: ${facility.contactPhone}', style: TextStyle(color: Colors.grey.shade700)),
              ),
            if (facility.websiteUrl.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(facility.websiteUrl, style: TextStyle(color: Colors.grey.shade700)),
              ),
          ],
          if (facility.cancellationPolicy.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Cancellation policy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(facility.cancellationPolicy, style: TextStyle(color: Colors.grey.shade700, height: 1.45)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.flash_on_rounded),
            label: const Text('Book This Venue'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: const Color(0xFF101218),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Venue Details', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: _AssetOrNetworkImage(
              networkImageUrl: facility.imageUrl,
              assetPath: visual.assetPath,
              fallbackImageUrl: visual.fallbackImageUrl,
              fit: BoxFit.cover,
              height: isWide ? 320 : 220,
              width: double.infinity,
            ),
          ),
          if (facility.galleryImageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: facility.galleryImageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    facility.galleryImageUrls[index],
                    width: 128,
                    height: 92,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 128,
                      height: 92,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!isWide) infoCard,
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoCard),
              ],
            ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B7280), fontSize: 12),
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
    if (networkImageUrl != null && networkImageUrl!.isNotEmpty) {
      return Image.network(
        networkImageUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return _fallback();
        },
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
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          fallbackImageUrl,
          width: width,
          height: height,
          fit: fit,
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
