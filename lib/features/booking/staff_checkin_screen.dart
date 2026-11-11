import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../auth/data/auth_session.dart';
import '../../shared/network/api_client.dart';
import '../../shared/ui/app_page_frame.dart';
import '../facility/facility_providers.dart';
import 'booking_providers.dart';
import 'booking_receipt_utils.dart';

class StaffCheckinScreen extends ConsumerStatefulWidget {
  const StaffCheckinScreen({super.key});

  @override
  ConsumerState<StaffCheckinScreen> createState() => _StaffCheckinScreenState();
}

class _StaffCheckinScreenState extends ConsumerState<StaffCheckinScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _scanning = false;
  bool _submitting = false;
  String? _lastScanned;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmScan(String token) async {
    if (_submitting || token.isEmpty || token == _lastScanned) return;
    setState(() {
      _submitting = true;
      _lastScanned = token;
      _message = null;
    });
    try {
      final session = ref.read(authSessionProvider);
      if (session == null) throw Exception('Please sign in again.');
      final result = await ref.read(apiClientProvider).postJson(
        '/api/bookings/check-in/',
        {'token': token},
        token: session.token,
      );
      ref.invalidate(bookingHistoryProvider);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _messageIsError = false;
        _message = 'Booking #${result['booking_id']} checked in at ${result['facility_name']}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venue Check-in'),
        actions: [
          IconButton(
            tooltip: 'Scan booking QR',
            onPressed: _submitting ? null : () => setState(() {
              _scanning = true;
              _lastScanned = null;
              _message = null;
            }),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: AppPageFrame(
        child: _scanning
            ? _buildScanner()
            : bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: OutlinedButton.icon(
                    onPressed: () => ref.invalidate(bookingHistoryProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload check-in queue'),
                  ),
                ),
                data: (bookings) {
                  final now = DateTime.now();
                  final upcoming = bookings.where((b) =>
                    b.endAt.isAfter(now) &&
                    b.status.toLowerCase() == 'confirmed' &&
                    b.paymentStatus.toLowerCase() == 'mock_paid'
                  ).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
                  final q = _searchCtrl.text.trim().toLowerCase();
                  final filtered = upcoming.where((b) =>
                    q.isEmpty ||
                    bookingReceiptId(b).toLowerCase().contains(q) ||
                    b.id.toString().contains(q) ||
                    b.facilityName.toLowerCase().contains(q)
                  ).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CUSTOMER ARRIVAL', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text('Scan the customer’s booking QR to verify payment and record their arrival.', style: TextStyle(color: Colors.white, fontSize: 15)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () => setState(() {
                                _scanning = true;
                                _lastScanned = null;
                                _message = null;
                              }),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scan customer QR'),
                            ),
                          ],
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _messageIsError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_message!, style: TextStyle(
                            color: _messageIsError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
                            fontWeight: FontWeight.w700,
                          )),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search receipt, booking or venue',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('${filtered.length} paid upcoming booking(s)', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ...filtered.map((b) => Card(
                        child: ListTile(
                          title: Text(b.facilityName, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${bookingReceiptId(b)} • ${DateFormat('EEE, dd MMM HH:mm').format(b.startAt)}'),
                          trailing: b.checkedInAt == null
                              ? const Icon(Icons.verified_user_outlined, color: Color(0xFF64748B))
                              : const Icon(Icons.check_circle, color: Color(0xFF059669)),
                        ),
                      )),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('Point the camera at the customer’s booking QR.', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => setState(() => _scanning = false), child: const Text('Cancel')),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: MobileScanner(
              onDetect: (capture) {
                final values = capture.barcodes
                    .map((barcode) => barcode.rawValue)
                    .whereType<String>();
                if (values.isNotEmpty) _confirmScan(values.first);
              },
            ),
          ),
        ),
        if (_submitting) const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
        if (_message != null) Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_message!, style: TextStyle(
            color: _messageIsError ? Colors.red : Colors.green,
            fontWeight: FontWeight.w700,
          )),
        ),
      ],
    );
  }
}
