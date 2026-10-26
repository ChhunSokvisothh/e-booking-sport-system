import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/models/models.dart';
import 'booking_providers.dart';
import 'booking_receipt_utils.dart';

class ReceiptCenterScreen extends ConsumerWidget {
  const ReceiptCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Center')),
      body: bookingsAsync.when(
        loading: () => const _ReceiptSkeletonList(),
        error: (error, stack) => Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(bookingHistoryProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reload Receipts'),
          ),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const Center(child: Text('No receipts available yet.'));
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(bookingHistoryProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              itemBuilder: (context, index) {
                final booking = bookings[index];
                return _ReceiptCard(booking: booking);
              },
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemCount: bookings.length,
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.booking});

  final BookingItem booking;

  @override
  Widget build(BuildContext context) {
    final receiptId = bookingReceiptId(booking);
    final qrPayload = bookingCheckinPayload(booking);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.facilityName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  receiptId,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: booking.status.toUpperCase(),
                color: booking.status == 'confirmed' ? const Color(0xFF065F46) : const Color(0xFF92400E),
                background: booking.status == 'confirmed' ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
              ),
              _StatusPill(
                label: booking.paymentStatus.replaceAll('_', ' ').toUpperCase(),
                color: booking.paymentStatus == 'mock_paid' ? const Color(0xFF1D4ED8) : const Color(0xFF6B7280),
                background: booking.paymentStatus == 'mock_paid' ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 440;
              final metaItems = <Widget>[
                _ReceiptMeta(label: 'Date', value: DateFormat('EEE, dd MMM yyyy').format(booking.startAt)),
                _ReceiptMeta(label: 'Time', value: '${DateFormat('HH:mm').format(booking.startAt)}-${DateFormat('HH:mm').format(booking.endAt)}'),
                _ReceiptMeta(label: 'Booking', value: '#${booking.id}'),
                _ReceiptMeta(label: 'Total', value: '\$${booking.finalPrice.toStringAsFixed(2)}', highlight: true),
                if (booking.couponCode.trim().isNotEmpty)
                  _ReceiptMeta(label: 'Coupon', value: booking.couponCode.toUpperCase()),
                if (booking.couponDiscount > 0)
                  _ReceiptMeta(label: 'Saved', value: '\$${booking.couponDiscount.toStringAsFixed(2)}', highlight: true),
              ];

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metaItems
                    .map(
                      (item) => SizedBox(
                        width: compact ? constraints.maxWidth : (constraints.maxWidth - 8) / 2,
                        child: item,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;

              final qrPreview = Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: QrImageView(data: qrPayload, version: QrVersions.auto, size: 74, gapless: false),
              );

              final action = FilledButton.tonalIcon(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(receiptId),
                      content: Center(
                        child: QrImageView(data: qrPayload, version: QrVersions.auto, size: 220, gapless: false),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('View Full QR'),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrPreview,
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: action),
                  ],
                );
              }

              return Row(
                children: [
                  qrPreview,
                  const SizedBox(width: 10),
                  Expanded(child: action),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReceiptMeta extends StatelessWidget {
  const _ReceiptMeta({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlight ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? const Color(0xFF1E40AF) : const Color(0xFF334155),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _ReceiptSkeletonList extends StatelessWidget {
  const _ReceiptSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      itemBuilder: (context, index) => Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemCount: 6,
    );
  }
}
