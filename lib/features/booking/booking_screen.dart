import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/ui/app_transitions.dart';
import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../../shared/ui/sport_visuals.dart';
import '../facility/facility_providers.dart';
import '../auth/auth_screen.dart';
import 'booking_providers.dart';
import 'booking_receipt_utils.dart';
import 'receipt_center_screen.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String _activeFilter = 'all';

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'GOOD MORNING';
    }
    if (hour < 18) {
      return 'GOOD AFTERNOON';
    }
    return 'GOOD NIGHT';
  }
  bool _isUpcoming(BookingItem booking) {
    if (booking.status.toLowerCase() == 'cancelled') {
      return false;
    }
    return booking.startAt.toLocal().isAfter(DateTime.now());
  }

  bool _isPast(BookingItem booking) {
    final status = booking.status.toLowerCase();
    if (status == 'cancelled') {
      return true;
    }
    return booking.endAt.toLocal().isBefore(DateTime.now());
  }

  bool _matchesFilter(BookingItem booking) {
    switch (_activeFilter) {
      case 'upcoming':
        return _isUpcoming(booking);
      case 'past':
        return _isPast(booking);
      default:
        return true;
    }
  }

  bool _canCancel(BookingItem booking) {
    final status = booking.status.toLowerCase();
    return booking.startAt.isAfter(DateTime.now()) && status != 'cancelled';
  }

  Future<void> _cancelBooking(BookingItem booking) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel booking?'),
          content: Text(
            'Cancel ${booking.facilityName} on ${DateFormat('dd MMM, HH:mm').format(booking.startAt)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final client = ref.read(apiClientProvider);
      await client.postJson('/api/bookings/${booking.id}/cancel/', {}, token: session.token);
      ref.invalidate(bookingHistoryProvider);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled. Slot is available again.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to cancel this booking right now. Please try again.')),
      );
    }
  }

  void _showBookingDetails(BuildContext context, BookingItem booking) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = booking.endAt.difference(booking.startAt).inMinutes / 60;
    final receiptId = bookingReceiptId(booking);
    final qrPayload = bookingCheckinPayload(booking);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: disableAnimations ? AnimationStyle.noAnimation : null,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.84),
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.facilityName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DetailStatusChip(
                            text: booking.status.toUpperCase(),
                            color: booking.status.toLowerCase() == 'confirmed' ? const Color(0xFF065F46) : const Color(0xFF92400E),
                            background: booking.status.toLowerCase() == 'confirmed' ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                          ),
                          _DetailStatusChip(
                            text: booking.paymentStatus.replaceAll('_', ' ').toUpperCase(),
                            color: booking.paymentStatus.toLowerCase() == 'mock_paid' ? const Color(0xFF1D4ED8) : const Color(0xFF6B7280),
                            background: booking.paymentStatus.toLowerCase() == 'mock_paid' ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _MetaCard(label: 'Booking ID', value: '#${booking.id}')),
                                  const SizedBox(width: 8),
                                  Expanded(child: _MetaCard(label: 'Receipt ID', value: receiptId)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _MetaCard(label: 'Duration', value: '${duration.toStringAsFixed(1)} hour(s)')),
                                  const SizedBox(width: 8),
                                  Expanded(child: _MetaCard(label: 'Amount', value: '\$${booking.finalPrice.toStringAsFixed(2)}', highlight: true)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _MetaCard(label: 'Start', value: DateFormat('EEE, dd MMM yyyy HH:mm').format(booking.startAt)),
                              const SizedBox(height: 8),
                              _MetaCard(label: 'End', value: DateFormat('EEE, dd MMM yyyy HH:mm').format(booking.endAt)),
                              if (booking.couponCode.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: _MetaCard(label: 'Coupon', value: booking.couponCode.toUpperCase())),
                                    if (booking.couponDiscount > 0) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _MetaCard(
                                          label: 'You Saved',
                                          value: '\$${booking.couponDiscount.toStringAsFixed(2)}',
                                          highlight: true,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 420;

                            final qr = QrImageView(
                              data: qrPayload,
                              version: QrVersions.auto,
                              size: compact ? 88 : 96,
                              gapless: false,
                            );

                            const text = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-in QR',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Show this QR at reception for faster verification.',
                                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                ),
                              ],
                            );

                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  text,
                                  const SizedBox(height: 8),
                                  Align(alignment: Alignment.centerLeft, child: qr),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                qr,
                                const SizedBox(width: 12),
                                const Expanded(child: text),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final largeText = textScale > 1.2;
    final compact = width < 430;
    final tablet = width >= 768;
    final horizontalPadding = width >= 1100 ? (width - 1000) / 2 : (compact ? 14.0 : 22.0);

    final session = ref.watch(authSessionProvider);
    final bookings = ref.watch(bookingHistoryProvider);
    final facilities = ref.watch(facilityListProvider).value ?? const <Facility>[];

    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 44),
              const SizedBox(height: 10),
              Text(
                'Login to view booking history',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'You can browse facilities as guest, but bookings and history require login.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text('Login Now'),
              ),
            ],
          ),
        ),
      );
    }

    return bookings.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No booking history yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use Quick Booking to create your first reservation.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        final byFacilityName = {
          for (final facility in facilities) facility.name.toLowerCase(): facility,
        };
        final filteredItems = items.where(_matchesFilter).toList();
        if (_activeFilter == 'upcoming') {
          filteredItems.sort((a, b) => a.startAt.compareTo(b.startAt));
        } else {
          filteredItems.sort((a, b) => b.startAt.compareTo(a.startAt));
        }
        final cardContentWidth = width - (horizontalPadding * 2);
        final twoColumns = cardContentWidth >= 860;

        return RefreshIndicator(
          onRefresh: () => ref.refresh(bookingHistoryProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 102),
            children: [
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
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _displayName(session.email),
                          style: TextStyle(
                            fontSize: tablet ? 40 : (compact ? 30 : 36),
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _HeaderCircleButton(
                    icon: Icons.notifications_none_rounded,
                    semanticLabel: 'Notifications',
                  ),
                  const SizedBox(width: 10),
                  const CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(
                      'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=200&q=80',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My\nBookings',
                      style: TextStyle(
                        fontSize: largeText ? 26 : 30,
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TabsBar(
                      activeValue: _activeFilter,
                      onTap: (value) => setState(() => _activeFilter = value),
                      compact: compact,
                      disableAnimations: disableAnimations,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'My\nBookings',
                        style: TextStyle(
                          fontSize: compact ? (largeText ? 25 : 28) : (largeText ? 31 : 34),
                          fontWeight: FontWeight.w900,
                          height: 0.95,
                        ),
                      ),
                    ),
                    _TabsBar(
                      activeValue: _activeFilter,
                      onTap: (value) => setState(() => _activeFilter = value),
                      compact: compact,
                      disableAnimations: disableAnimations,
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(buildSlideFadeRoute(const ReceiptCenterScreen()));
                    },
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Receipt Center'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (filteredItems.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _activeFilter == 'upcoming'
                        ? 'No upcoming bookings yet.'
                        : _activeFilter == 'past'
                            ? 'No past bookings yet.'
                            : 'No bookings yet.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                if (twoColumns)
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: filteredItems.map((booking) {
                      final facility = byFacilityName[booking.facilityName.toLowerCase()];
                      final visual = SportVisuals.of(facility?.sportType);
                      return SizedBox(
                        width: (cardContentWidth - 14) / 2,
                        child: _BookingHistoryCard(
                          booking: booking,
                          imageAsset: visual.assetPath,
                          imageUrl: visual.fallbackImageUrl,
                          location: facility?.locationName ?? 'Sports Complex',
                          compact: compact,
                          largeText: largeText,
                          statusLabel: booking.status.toLowerCase() == 'cancelled'
                              ? 'Cancelled'
                              : _isUpcoming(booking)
                                  ? 'Upcoming'
                                  : 'Completed',
                          canCancel: _canCancel(booking),
                          onCancel: () => _cancelBooking(booking),
                          onDetails: () => _showBookingDetails(context, booking),
                        ),
                      );
                    }).toList(),
                  )
                else
                  ...filteredItems.map((booking) {
                    final facility = byFacilityName[booking.facilityName.toLowerCase()];
                    final visual = SportVisuals.of(facility?.sportType);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _BookingHistoryCard(
                        booking: booking,
                        imageAsset: visual.assetPath,
                        imageUrl: visual.fallbackImageUrl,
                        location: facility?.locationName ?? 'Sports Complex',
                        compact: compact,
                        largeText: largeText,
                        statusLabel: booking.status.toLowerCase() == 'cancelled'
                            ? 'Cancelled'
                            : _isUpcoming(booking)
                                ? 'Upcoming'
                                : 'Completed',
                        canCancel: _canCancel(booking),
                        onCancel: () => _cancelBooking(booking),
                        onDetails: () => _showBookingDetails(context, booking),
                      ),
                    );
                  }),
            ],
          ),
        );
      },
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unable to load booking history right now.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(bookingHistoryProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
      loading: () => const _BookingsSkeleton(),
    );
  }

  String _displayName(String email) {
    final raw = email.split('@').first;
    final parts = raw.split(RegExp(r'[._-]+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'Sports Lover';
    }
    return parts
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _BookingsSkeleton extends StatelessWidget {
  const _BookingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemBuilder: (context, index) => Container(
        height: 210,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemCount: 4,
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.label, required this.value, this.highlight = false});

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
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? const Color(0xFF1E40AF) : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailStatusChip extends StatelessWidget {
  const _DetailStatusChip({required this.text, required this.color, required this.background});

  final String text;
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
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.semanticLabel});

  final IconData icon;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: IconButton(onPressed: () {}, icon: Icon(icon, size: 22)),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.value,
    required this.activeValue,
    required this.onTap,
    required this.disableAnimations,
  });

  final String label;
  final String value;
  final String activeValue;
  final ValueChanged<String> onTap;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final selected = value == activeValue;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter $label',
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF111318) : const Color(0xFFA2A7B1),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({
    required this.activeValue,
    required this.onTap,
    required this.compact,
    required this.disableAnimations,
  });

  final String activeValue;
  final ValueChanged<String> onTap;
  final bool compact;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final tabs = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentTab(
          label: 'ALL',
          value: 'all',
          activeValue: activeValue,
          onTap: onTap,
          disableAnimations: disableAnimations,
        ),
        _SegmentTab(
          label: 'UPCOMING',
          value: 'upcoming',
          activeValue: activeValue,
          onTap: onTap,
          disableAnimations: disableAnimations,
        ),
        _SegmentTab(
          label: 'PAST',
          value: 'past',
          activeValue: activeValue,
          onTap: onTap,
          disableAnimations: disableAnimations,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tabs,
            )
          : tabs,
    );
  }
}

class _BookingHistoryCard extends StatelessWidget {
  const _BookingHistoryCard({
    required this.booking,
    required this.imageAsset,
    required this.imageUrl,
    required this.location,
    required this.compact,
    required this.largeText,
    required this.statusLabel,
    required this.canCancel,
    required this.onCancel,
    required this.onDetails,
  });

  final BookingItem booking;
  final String imageAsset;
  final String imageUrl;
  final String location;
  final bool compact;
  final bool largeText;
  final String statusLabel;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM dd, yyyy').format(booking.startAt.toLocal());
    final timeLabel = DateFormat('HH:mm').format(booking.startAt.toLocal());
    final lowerStatus = statusLabel.toLowerCase();
    final statusColor = lowerStatus == 'completed'
        ? const Color(0xFF047857)
        : lowerStatus == 'cancelled'
            ? const Color(0xFFDC2626)
            : const Color(0xFF2F6DF8);
    final statusBackground = lowerStatus == 'completed'
      ? const Color(0xFFE6F7EF)
      : lowerStatus == 'cancelled'
        ? const Color(0xFFFEECEC)
        : const Color(0xFFEAF1FF);
    final imageSize = compact ? 84.0 : 96.0;
    final titleSize = compact ? 15.0 : 16.0;
    final amountSize = compact ? 21.0 : 23.0;

    return Semantics(
      container: true,
      label: '${booking.facilityName} booking card, status $statusLabel, at $timeLabel on $dateLabel',
      child: Container(
      padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  imageAsset,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) {
                    return Image.network(imageUrl, width: imageSize, height: imageSize, fit: BoxFit.cover);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (largeText)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.facilityName,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w900, height: 1.15),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusBackground,
                              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              booking.facilityName,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w900, height: 1.15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusBackground,
                              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      location,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        Text(
                          dateLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563), fontSize: 13),
                        ),
                        Text(
                          timeLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563), fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = compact || constraints.maxWidth < 360;
              final priceText = Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B1320), Color(0xFF1F2937)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.payments, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      '\$${booking.finalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: amountSize,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Total',
                      style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              );

              final actions = Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (canCancel)
                    FilledButton.tonal(
                      onPressed: onCancel,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF1F2),
                        foregroundColor: const Color(0xFFFF1A1A),
                        minimumSize: Size(compact ? 76 : 88, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  FilledButton(
                    onPressed: onDetails,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111318),
                      foregroundColor: Colors.white,
                      minimumSize: Size(compact ? 90 : 104, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Details', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    priceText,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: priceText,
                    ),
                  ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        ),
      ),
    );
  }
}
