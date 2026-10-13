import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'booking_providers.dart';
import 'booking_receipt_utils.dart';

class StaffCheckinScreen extends ConsumerStatefulWidget {
  const StaffCheckinScreen({super.key});

  @override
  ConsumerState<StaffCheckinScreen> createState() => _StaffCheckinScreenState();
}

class _StaffCheckinScreenState extends ConsumerState<StaffCheckinScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _checkedInBookingIds = <int>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _markCheckedIn(int bookingId) {
    setState(() => _checkedInBookingIds.add(bookingId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Booking #$bookingId checked in successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff Check-in Desk')),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(bookingHistoryProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reload Check-in Queue'),
          ),
        ),
        data: (bookings) {
          final now = DateTime.now();
          final upcoming = bookings
              .where((b) => b.endAt.isAfter(now) && b.status.toLowerCase() != 'cancelled')
              .toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));

          final q = _searchCtrl.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? upcoming
              : upcoming.where((b) {
                  final receiptId = bookingReceiptId(b).toLowerCase();
                  return receiptId.contains(q) ||
                      b.id.toString().contains(q) ||
                      b.facilityName.toLowerCase().contains(q);
                }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF334155)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Search by receipt ID, booking ID, or venue and confirm arrivals quickly.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search receipt / booking / facility',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${filtered.length} booking(s) in queue',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Text('No bookings match your search.'),
                )
              else
                ...filtered.map(
                  (b) {
                    final checked = _checkedInBookingIds.contains(b.id);
                    final receiptId = bookingReceiptId(b);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  b.facilityName,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: checked ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  checked ? 'Checked-in' : 'Awaiting',
                                  style: TextStyle(
                                    color: checked ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Receipt: $receiptId', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Booking #${b.id} • ${DateFormat('EEE, dd MMM HH:mm').format(b.startAt)}'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: checked ? null : () => _markCheckedIn(b.id),
                            icon: const Icon(Icons.how_to_reg),
                            label: Text(checked ? 'Already Checked-in' : 'Confirm Check-in'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
