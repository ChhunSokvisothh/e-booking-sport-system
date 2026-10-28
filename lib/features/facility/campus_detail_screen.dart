import 'package:flutter/material.dart';

import '../../shared/models/models.dart';
import '../booking/quick_book_screen.dart';

class CampusDetailScreen extends StatelessWidget {
  const CampusDetailScreen({
    super.key,
    required this.campus,
    required this.onOpenDashboard,
  });

  final Map<String, dynamic> campus;
  final VoidCallback onOpenDashboard;

  @override
  Widget build(BuildContext context) {
    final name = (campus['name'] ?? 'Sports campus').toString();
    final description = (campus['description'] ?? '').toString().trim();
    final address = (campus['address'] ?? '').toString();
    final cover = (campus['cover_image_url'] ?? '').toString();
    final photos = (campus['photos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((photo) => (photo['image_url'] ?? '').toString())
        .where((url) => url.startsWith('http://') || url.startsWith('https://'))
        .toList();
    final amenities = (campus['amenities'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final hours = campus['opening_hours'] as Map<String, dynamic>? ?? const {};
    final facilities = (campus['facilities'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Facility.fromJson)
        .toList();
    final policy = (campus['cancellation_policy'] ?? '').toString().trim();
    final phone = (campus['contact_phone'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(title: const Text('Campus details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: cover.isEmpty
                ? Container(
                    height: 220,
                    color: const Color(0xFF172554),
                    alignment: Alignment.center,
                    child: const Icon(Icons.sports_soccer, color: Colors.white, size: 64),
                  )
                : Image.network(
                    cover,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 220,
                      color: const Color(0xFF172554),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.white, size: 48),
                    ),
                  ),
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photos[index],
                    width: 132,
                    height: 92,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 132,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_outlined, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(address, style: TextStyle(color: Colors.grey.shade700))),
            ]),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('About this campus', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(description, style: TextStyle(color: Colors.grey.shade700, height: 1.5)),
          ],
          if (amenities.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Facilities & amenities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: amenities.map((item) => Chip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(item),
              )).toList(),
            ),
          ],
          if (hours.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Opening hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...hours.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(entry.value.toString()),
              ]),
            )),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Contact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(children: [const Icon(Icons.phone_outlined), const SizedBox(width: 8), Text(phone)]),
          ],
          if (policy.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Cancellation policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(policy, style: TextStyle(color: Colors.grey.shade700, height: 1.45)),
          ],
          const SizedBox(height: 24),
          const Text('Book a court or facility', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (facilities.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No bookable facilities have been published for this campus yet.'),
            )),
          ...facilities.map((facility) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(child: Icon(facility.isIndoor ? Icons.stadium_outlined : Icons.sports_soccer)),
              title: Text(facility.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${facility.sportType.toUpperCase()} · ${facility.isIndoor ? 'Indoor' : 'Outdoor'}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$${facility.basePricePerHour.toStringAsFixed(0)}/hr', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Text('View slots', style: TextStyle(fontSize: 11)),
                ],
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => QuickBookScreen(
                  onOpenDashboard: onOpenDashboard,
                  initialSportType: facility.sportType,
                  initialFacilityId: facility.id.toString(),
                ),
              )),
            ),
          )),
        ],
      ),
    );
  }
}
