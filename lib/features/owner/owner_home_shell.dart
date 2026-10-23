import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../shared/ui/app_transitions.dart';
import '../auth/data/auth_session.dart';
import '../../shared/platform/file_download.dart';
import '../../shared/models/models.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../booking/booking_providers.dart';
import '../booking/staff_checkin_screen.dart';
import '../facility/facility_providers.dart';
import 'owner_archive_records_screen.dart';
import 'owner_coupon_screen.dart';

enum OwnerDashboardRange { today, sevenDays, thirtyDays }

extension OwnerDashboardRangeX on OwnerDashboardRange {
  String get label {
    switch (this) {
      case OwnerDashboardRange.today:
        return 'Today';
      case OwnerDashboardRange.sevenDays:
        return '7 Days';
      case OwnerDashboardRange.thirtyDays:
        return '30 Days';
    }
  }

  int get days {
    switch (this) {
      case OwnerDashboardRange.today:
        return 1;
      case OwnerDashboardRange.sevenDays:
        return 7;
      case OwnerDashboardRange.thirtyDays:
        return 30;
    }
  }
}

class OwnerHomeShell extends ConsumerStatefulWidget {
  const OwnerHomeShell({super.key});

  @override
  ConsumerState<OwnerHomeShell> createState() => _OwnerHomeShellState();
}

class _OwnerHomeShellState extends ConsumerState<OwnerHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final pages = [
      const _OwnerDashboardTab(),
      const _OwnerHistoryTab(),
      const _OwnerFacilitiesTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        title: const Text('Owner Console'),
        actions: [
          IconButton(
            tooltip: 'Archive Records',
            onPressed: () {
              Navigator.of(context).push(buildSlideFadeRoute(const OwnerArchiveRecordsScreen()));
            },
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Manage Coupons',
            onPressed: () {
              Navigator.of(context).push(buildSlideFadeRoute(const OwnerCouponScreen()));
            },
            icon: const Icon(Icons.local_offer_outlined),
          ),
          IconButton(
            tooltip: 'Staff Check-in',
            onPressed: () {
              Navigator.of(context).push(buildSlideFadeRoute(const StaffCheckinScreen()));
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(authControllerProvider).logout();
              if (!mounted) {
                return;
              }
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.history_outlined), label: 'History'),
          NavigationDestination(icon: Icon(Icons.stadium_outlined), label: 'Venues'),
        ],
      ),
      floatingActionButton: session == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () {},
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text('Owner: ${session.email.split('@').first}'),
            ),
    );
  }
}

class _OwnerDashboardTab extends ConsumerStatefulWidget {
  const _OwnerDashboardTab();

  @override
  ConsumerState<_OwnerDashboardTab> createState() => _OwnerDashboardTabState();
}

class _OwnerDashboardTabState extends ConsumerState<_OwnerDashboardTab> {
  OwnerDashboardRange _range = OwnerDashboardRange.sevenDays;

  List<Facility>? _cachedFacilities;
  List<BookingItem>? _cachedBookings;
  DateTime? _lastSyncedAt;

  Widget _buildDashboardMetrics(List<BookingItem> bookingRows, int activeVenues) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final rangeStart = _range == OwnerDashboardRange.today
        ? today
        : today.subtract(Duration(days: _range.days - 1));
    final bookingsInRange = bookingRows.where((b) => !b.startAt.isBefore(rangeStart) && b.startAt.isBefore(tomorrow)).toList();
    final bookingsToday = bookingRows.where((b) => !b.startAt.isBefore(today) && b.startAt.isBefore(tomorrow)).toList();
    final confirmedToday = bookingsToday.where((b) => b.status == 'confirmed').length;
    final todayRevenue = bookingsToday.where((b) => b.paymentStatus == 'mock_paid').fold<double>(0, (sum, row) => sum + row.finalPrice);
    final pendingPayments = bookingRows.where((b) => b.paymentStatus == 'mock_pending').length;
    final redeemedCount = bookingsInRange.where((b) => b.couponCode.trim().isNotEmpty).length;
    final couponRevenueImpact = bookingsInRange.fold<double>(0, (sum, b) => sum + b.couponDiscount);
    final couponStatsMap = <String, ({int uses, double savings, double revenue})>{};
    for (final booking in bookingsInRange.where((b) => b.couponCode.trim().isNotEmpty)) {
      final code = booking.couponCode.trim().toUpperCase();
      final current = couponStatsMap[code];
      couponStatsMap[code] = (
        uses: (current?.uses ?? 0) + 1,
        savings: (current?.savings ?? 0) + booking.couponDiscount,
        revenue: (current?.revenue ?? 0) + booking.finalPrice,
      );
    }
    final couponStats = couponStatsMap.entries.toList()
      ..sort((a, b) {
        final byUses = b.value.uses.compareTo(a.value.uses);
        if (byUses != 0) {
          return byUses;
        }
        return b.value.savings.compareTo(a.value.savings);
      });

    final revenueInRange = bookingsInRange.where((b) => b.paymentStatus == 'mock_paid').fold<double>(0, (sum, row) => sum + row.finalPrice);

    final revenueByFacility = <String, double>{};
    for (final booking in bookingsInRange.where((b) => b.paymentStatus == 'mock_paid')) {
      revenueByFacility[booking.facilityName] = (revenueByFacility[booking.facilityName] ?? 0) + booking.finalPrice;
    }

    String topVenueName = 'No sales yet';
    double topVenueRevenue = 0;
    revenueByFacility.forEach((name, value) {
      if (value > topVenueRevenue) {
        topVenueName = name;
        topVenueRevenue = value;
      }
    });

    final bookedHours = bookingsInRange.fold<double>(
      0,
      (sum, booking) => sum + booking.endAt.difference(booking.startAt).inMinutes / 60,
    );
    final capacityHours = (activeVenues <= 0 ? 1 : activeVenues) * 14 * _range.days;
    final occupancyRate = ((bookedHours / capacityHours) * 100).clamp(0, 100).toDouble();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Bookings Today',
                value: bookingsToday.length.toString(),
                icon: Icons.event_available,
                color: const Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Revenue Today (USD)',
                value: '\$${todayRevenue.toStringAsFixed(2)}',
                icon: Icons.attach_money,
                color: const Color(0xFF1D4ED8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Bookings (${_range.label})',
                value: bookingsInRange.length.toString(),
                icon: Icons.query_stats,
                color: const Color(0xFF047857),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Revenue (${_range.label})',
                value: '\$${revenueInRange.toStringAsFixed(2)}',
                icon: Icons.stacked_line_chart,
                color: const Color(0xFFB45309),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Confirmed Today',
                value: confirmedToday.toString(),
                icon: Icons.verified,
                color: const Color(0xFF0EA5E9),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Pending Payment',
                value: pendingPayments.toString(),
                icon: Icons.pending_actions,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Coupon Redemptions',
                value: redeemedCount.toString(),
                icon: Icons.local_offer,
                color: const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Coupon Impact',
                value: '\$${couponRevenueImpact.toStringAsFixed(2)}',
                icon: Icons.trending_down,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _TopVenueAndOccupancyCard(
          topVenueName: topVenueName,
          topVenueRevenue: topVenueRevenue,
          occupancyRate: occupancyRate,
          rangeLabel: _range.label,
        ),
        const SizedBox(height: 14),
        _RevenueMiniTrend(
          bookings: bookingRows,
          days: _range.days,
          title: 'Revenue Trend (${_range.label})',
        ),
        const SizedBox(height: 14),
        _CouponPerformanceCard(couponStats: couponStats, rangeLabel: _range.label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final facilities = ref.watch(ownerFacilitiesProvider);
    final bookings = ref.watch(bookingHistoryProvider);
    final session = ref.watch(authSessionProvider);

    if (facilities.hasValue) {
      _cachedFacilities = List<Facility>.from(facilities.asData!.value);
    }
    if (bookings.hasValue) {
      _cachedBookings = List<BookingItem>.from(bookings.asData!.value);
    }
    if (facilities.hasValue && bookings.hasValue) {
      _lastSyncedAt = DateTime.now();
    }

    final effectiveFacilities = facilities.asData?.value ?? _cachedFacilities;
    final effectiveBookings = bookings.asData?.value ?? _cachedBookings;
    final activeVenueCount = effectiveFacilities?.where((e) => e.basePricePerHour > 0).length ?? 0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ownerFacilitiesProvider);
        ref.invalidate(bookingHistoryProvider);
        await Future.wait([
          ref.read(ownerFacilitiesProvider.future),
          ref.read(bookingHistoryProvider.future),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _OwnerHeroCard(ownerEmail: session?.email ?? 'owner@example.com'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync, size: 16, color: Color(0xFF1E293B)),
                const SizedBox(width: 6),
                Text(
                  _lastSyncedAt == null
                      ? 'Records are being prepared.'
                      : 'Records were updated at ${DateFormat('HH:mm:ss').format(_lastSyncedAt!)}.',
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OwnerDashboardRange.values.map((item) {
                final selected = _range == item;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.label),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: const Color(0xFF0F172A),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF1F2937),
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) {
                      setState(() => _range = item);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (effectiveBookings == null)
            const _DashboardLoadingBlock()
          else
            _buildDashboardMetrics(effectiveBookings, activeVenueCount),
          const SizedBox(height: 14),
          if (effectiveFacilities == null)
            const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _InlineStat(label: 'Total Venues', value: effectiveFacilities.length.toString()),
                  ),
                  Expanded(
                    child: _InlineStat(label: 'Indoor', value: effectiveFacilities.where((e) => e.isIndoor).length.toString()),
                  ),
                  Expanded(
                    child: _InlineStat(label: 'Outdoor', value: effectiveFacilities.where((e) => !e.isIndoor).length.toString()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnerHistoryTab extends ConsumerStatefulWidget {
  const _OwnerHistoryTab();

  @override
  ConsumerState<_OwnerHistoryTab> createState() => _OwnerHistoryTabState();
}

class _OwnerHistoryTabState extends ConsumerState<_OwnerHistoryTab> {
  OwnerDashboardRange _range = OwnerDashboardRange.sevenDays;
  List<BookingItem>? _cachedHistoryRows;

  String _toCsv(List<BookingItem> rows) {
    String cell(String value) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }

    final buffer = StringBuffer();
    buffer.writeln('booking_id,facility,status,payment_status,start_at,end_at,amount_usd,booking_source');
    for (final row in rows) {
      buffer.writeln([
        row.id,
        cell(row.facilityName),
        cell(row.status),
        cell(row.paymentStatus),
        cell(row.startAt.toIso8601String()),
        cell(row.endAt.toIso8601String()),
        row.finalPrice.toStringAsFixed(2),
        cell(row.bookingSource),
      ].join(','));
    }
    return buffer.toString();
  }

  Future<void> _exportCsv(List<BookingItem> rows) async {
    final csv = _toCsv(rows);
    final formatter = DateFormat('yyyyMMdd_HHmm');
    final fileName = 'owner_booking_history_${formatter.format(DateTime.now())}.csv';
    final downloaded = await downloadBytes(
      fileName: fileName,
      bytes: csv.codeUnits,
      mimeType: 'text/csv;charset=utf-8',
    );

    if (!mounted) {
      return;
    }

    if (downloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV downloaded: $fileName')),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard (download unsupported on this platform).')),
      );
    }
  }

  Future<void> _exportPdf(List<BookingItem> rows) async {
    final doc = pw.Document();
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final total = rows.fold<double>(0, (sum, row) => sum + row.finalPrice);
    final paidTotal = rows
        .where((row) => row.paymentStatus.toLowerCase() == 'mock_paid')
        .fold<double>(0, (sum, row) => sum + row.finalPrice);
    final confirmedCount = rows.where((row) => row.status.toLowerCase() == 'confirmed').length;
    final pendingCount = rows.where((row) => row.paymentStatus.toLowerCase() == 'mock_pending').length;
    final venueCount = rows.map((row) => row.facilityName).toSet().length;

    pw.Widget statCard(String label, String value, PdfColor color) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.blueGrey200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey700)),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(12),
              gradient: const pw.LinearGradient(
                colors: [PdfColor.fromInt(0xFF0F172A), PdfColor.fromInt(0xFF334155)],
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 28,
                  height: 28,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Owner Booking History Report',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Generated ${formatter.format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue100),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              statCard('Records', rows.length.toString(), PdfColors.blue900),
              statCard('Confirmed', confirmedCount.toString(), PdfColors.green700),
              statCard('Pending', pendingCount.toString(), PdfColors.orange700),
              statCard('Venues', venueCount.toString(), PdfColors.indigo700),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              statCard('Total Amount', 'USD ${total.toStringAsFixed(2)}', PdfColors.blue800),
              statCard('Paid Amount', 'USD ${paidTotal.toStringAsFixed(2)}', PdfColors.teal700),
              pw.Expanded(child: pw.SizedBox()),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('Booking Details', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Booking ID', 'Facility', 'Status', 'Payment', 'Start', 'End', 'Amount'],
            data: rows
                .map(
                  (row) => [
                    '#${row.id}',
                    row.facilityName,
                    row.status,
                    row.paymentStatus,
                    DateFormat('yyyy-MM-dd HH:mm').format(row.startAt),
                    DateFormat('yyyy-MM-dd HH:mm').format(row.endAt),
                    row.finalPrice.toStringAsFixed(2),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final fileName = 'owner_booking_history_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    final downloaded = await downloadBytes(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
    );

    if (!mounted) {
      return;
    }

    if (downloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF downloaded: $fileName')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF download is supported on web.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingHistoryProvider);

    if (bookingsAsync.hasValue) {
      _cachedHistoryRows = List<BookingItem>.from(bookingsAsync.asData!.value);
    }

    final rows = bookingsAsync.asData?.value ?? _cachedHistoryRows;

    if (rows == null) {
      if (bookingsAsync.hasError) {
        return Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(bookingHistoryProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reload History'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (rows.isEmpty) {
      return const Center(child: Text('No booking history found yet.'));
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));
    final start = _range == OwnerDashboardRange.today
        ? today
        : today.subtract(Duration(days: _range.days - 1));

    final filtered = rows
        .where((b) => !b.startAt.isBefore(start) && b.startAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

    return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: OwnerDashboardRange.values.map((item) {
                        final selected = _range == item;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(item.label),
                            selected: selected,
                            showCheckmark: false,
                            selectedColor: const Color(0xFF0F172A),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF1F2937),
                              fontWeight: FontWeight.w800,
                            ),
                            onSelected: (_) {
                              setState(() => _range = item);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('CSV'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: filtered.isEmpty ? null : () => _exportPdf(filtered),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text('No history in ${_range.label.toLowerCase()}.'),
              )
            else
              ...filtered.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OwnerBookingHistoryCard(item: item),
                ),
              ),
          ],
        );
  }
}

class _OwnerFacilitiesTab extends ConsumerStatefulWidget {
  const _OwnerFacilitiesTab();

  @override
  ConsumerState<_OwnerFacilitiesTab> createState() => _OwnerFacilitiesTabState();
}

class _OwnerFacilitiesTabState extends ConsumerState<_OwnerFacilitiesTab> {
  int? _processingFacilityId;
  bool _savingNewVenue = false;
  String _statusFilter = 'all';
  String _venueSearchText = '';
  List<Facility>? _ownerRows;
  int? _highlightedFacilityId;

  void _flashFacilityRow(int facilityId) {
    setState(() => _highlightedFacilityId = facilityId);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _highlightedFacilityId != facilityId) {
        return;
      }
      setState(() => _highlightedFacilityId = null);
    });
  }

  static const List<String> _sportTypes = [
    'football',
    'billiard',
    'pickleball',
    'volleyball',
    'basketball',
    'futsal',
    'tennis',
    'badminton',
  ];

  Facility? _facilityFromResponse(Map<String, dynamic> response) {
    final raw = response['facility'];
    if (raw is Map<String, dynamic>) {
      return Facility.fromJson(raw);
    }
    if (raw is Map) {
      return Facility.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  void _upsertOwnerRow(Facility facility) {
    final source = List<Facility>.from(_ownerRows ?? const <Facility>[]);
    final idx = source.indexWhere((row) => row.id == facility.id);
    if (idx >= 0) {
      source[idx] = facility;
    } else {
      source.add(facility);
    }
    source.sort((a, b) {
      final sportSort = a.sportType.compareTo(b.sportType);
      if (sportSort != 0) {
        return sportSort;
      }
      return a.name.compareTo(b.name);
    });
    setState(() => _ownerRows = source);
    _flashFacilityRow(facility.id);
  }

  void _invalidateRelatedVenueProviders() {
    ref.invalidate(ownerFacilitiesProvider);
    ref.invalidate(facilityListProvider);
    ref.invalidate(facilityListByQueryProvider);
    ref.invalidate(facilityListByQueryWithDiagnosticsProvider);
    ref.invalidate(liveSlotAvailabilityProvider);
    ref.invalidate(liveSlotAvailabilityWithDiagnosticsProvider);
  }

  Future<void> _showAddVenueDialog() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final latitudeCtrl = TextEditingController(text: '11.5564');
    final longitudeCtrl = TextEditingController(text: '104.9282');
    bool isIndoor = false;
    String sportType = _sportTypes.first;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Venue'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Venue Name')),
                    const SizedBox(height: 8),
                    TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location')),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: sportType,
                      decoration: const InputDecoration(labelText: 'Sport Type'),
                      items: _sportTypes
                          .map((item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item.toUpperCase()),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => sportType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price Per Hour (USD)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: descriptionCtrl, decoration: const InputDecoration(labelText: 'Description (optional)')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latitudeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: longitudeCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isIndoor,
                      title: const Text('Indoor Venue'),
                      onChanged: (value) => setDialogState(() => isIndoor = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Create Venue')),
              ],
            );
          },
        );
      },
    );

    if (created != true) {
      return;
    }

    setState(() => _savingNewVenue = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.postJson(
        '/api/facilities/owner/',
        {
          'name': nameCtrl.text,
          'location_name': locationCtrl.text,
          'sport_type': sportType,
          'base_price_per_hour': priceCtrl.text,
          'description': descriptionCtrl.text,
          'latitude': latitudeCtrl.text,
          'longitude': longitudeCtrl.text,
          'is_indoor': isIndoor,
        },
        token: session.token,
      );
      final createdFacility = _facilityFromResponse(response);
      if (createdFacility != null) {
        _upsertOwnerRow(createdFacility);
      }
      _invalidateRelatedVenueProviders();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue created successfully.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _savingNewVenue = false);
      }
    }
  }

  Future<void> _updateVenuePrice(Facility facility) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final priceCtrl = TextEditingController(text: facility.basePricePerHour.toStringAsFixed(2));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update Price: ${facility.name}'),
        content: TextField(
          controller: priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'New Price Per Hour (USD)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Update')),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() => _processingFacilityId = facility.id);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.patchJson(
        '/api/facilities/owner/${facility.id}/',
        {'base_price_per_hour': priceCtrl.text},
        token: session.token,
      );
      final updatedFacility = _facilityFromResponse(response);
      if (updatedFacility != null) {
        _upsertOwnerRow(updatedFacility);
      }
      _invalidateRelatedVenueProviders();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue price updated.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _processingFacilityId = null);
      }
    }
  }

  Future<void> _editVenueDetails(Facility facility) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final nameCtrl = TextEditingController(text: facility.name);
    final locationCtrl = TextEditingController(text: facility.locationName);
    final priceCtrl = TextEditingController(text: facility.basePricePerHour.toStringAsFixed(2));
    final descriptionCtrl = TextEditingController(text: facility.description);
    final latitudeCtrl = TextEditingController(text: facility.latitude.toString());
    final longitudeCtrl = TextEditingController(text: facility.longitude.toString());
    final imageUrlCtrl = TextEditingController(text: facility.imageUrl ?? '');
    bool isIndoor = facility.isIndoor;
    String sportType = _sportTypes.contains(facility.sportType) ? facility.sportType : _sportTypes.first;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Venue Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Venue Name')),
                  const SizedBox(height: 8),
                  TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: sportType,
                    decoration: const InputDecoration(labelText: 'Sport Type'),
                    items: _sportTypes
                        .map((item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(item.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => sportType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price Per Hour (USD)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: descriptionCtrl, decoration: const InputDecoration(labelText: 'Description')),
                  const SizedBox(height: 8),
                  TextField(controller: imageUrlCtrl, decoration: const InputDecoration(labelText: 'Image URL (optional)')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitudeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: const InputDecoration(labelText: 'Latitude'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: longitudeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: const InputDecoration(labelText: 'Longitude'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isIndoor,
                    title: const Text('Indoor Venue'),
                    onChanged: (value) => setDialogState(() => isIndoor = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save Changes')),
            ],
          ),
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _processingFacilityId = facility.id);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.patchJson(
        '/api/facilities/owner/${facility.id}/',
        {
          'name': nameCtrl.text,
          'location_name': locationCtrl.text,
          'sport_type': sportType,
          'base_price_per_hour': priceCtrl.text,
          'description': descriptionCtrl.text,
          'image_url': imageUrlCtrl.text,
          'latitude': latitudeCtrl.text,
          'longitude': longitudeCtrl.text,
          'is_indoor': isIndoor,
        },
        token: session.token,
      );
      final updatedFacility = _facilityFromResponse(response);
      if (updatedFacility != null) {
        _upsertOwnerRow(updatedFacility);
      }
      _invalidateRelatedVenueProviders();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue updated successfully.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _processingFacilityId = null);
      }
    }
  }

  Future<void> _archiveVenue(Facility facility) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive venue?'),
        content: Text('${facility.name} will be archived and hidden from users.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Archive')),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() => _processingFacilityId = facility.id);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.deleteJson('/api/facilities/owner/${facility.id}/', token: session.token);
      final updatedFacility = _facilityFromResponse(response);
      if (updatedFacility != null) {
        _upsertOwnerRow(updatedFacility);
      }
      _invalidateRelatedVenueProviders();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue archived.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _processingFacilityId = null);
      }
    }
  }

  Future<void> _restoreVenue(Facility facility) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    setState(() => _processingFacilityId = facility.id);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.patchJson('/api/facilities/owner/${facility.id}/', {'is_active': true}, token: session.token);
      final updatedFacility = _facilityFromResponse(response);
      if (updatedFacility != null) {
        _upsertOwnerRow(updatedFacility);
      }
      _invalidateRelatedVenueProviders();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue restored.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) {
        setState(() => _processingFacilityId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final facilities = ref.watch(ownerFacilitiesProvider);

    return facilities.when(
      loading: () {
        if (_ownerRows != null) {
          return _buildFacilityList(_ownerRows!);
        }
        return const Center(child: CircularProgressIndicator());
      },
      error: (error, stack) {
        if (_ownerRows != null) {
          return _buildFacilityList(_ownerRows!);
        }
        return Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(ownerFacilitiesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Reload Venues'),
          ),
        );
      },
      data: (rows) {
        _ownerRows = List<Facility>.from(rows);
        return _buildFacilityList(_ownerRows!);
      },
    );
  }

  Widget _buildFacilityList(List<Facility> rows) {
    final totalCount = rows.length;
    final archivedCount = rows.where((item) => item.archivedAt != null || !item.isActive).length;
    final activeCount = totalCount - archivedCount;

    final normalizedSearch = _venueSearchText.trim().toLowerCase();
    final filteredRows = rows.where((item) {
          final isArchived = item.archivedAt != null || !item.isActive;
          if (_statusFilter == 'active') {
            if (isArchived) {
              return false;
            }
          }
          if (_statusFilter == 'archived') {
            if (!isArchived) {
              return false;
            }
          }
          if (normalizedSearch.isEmpty) {
            return true;
          }

          final haystack = '${item.name} ${item.locationName} ${item.sportType}'.toLowerCase();
          return haystack.contains(normalizedSearch);
        }).toList();

    return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
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
                          'Create a new venue and set its price. You can update pricing anytime.',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _savingNewVenue ? null : _showAddVenueDialog,
                        icon: _savingNewVenue
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_business_outlined),
                        label: Text(_savingNewVenue ? 'Saving...' : 'Add Venue'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('All ($totalCount)'),
                        selected: _statusFilter == 'all',
                        onSelected: (_) => setState(() => _statusFilter = 'all'),
                      ),
                      ChoiceChip(
                        label: Text('Active ($activeCount)'),
                        selected: _statusFilter == 'active',
                        onSelected: (_) => setState(() => _statusFilter = 'active'),
                      ),
                      ChoiceChip(
                        label: Text('Archived ($archivedCount)'),
                        selected: _statusFilter == 'archived',
                        onSelected: (_) => setState(() => _statusFilter = 'archived'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setState(() => _venueSearchText = value),
                    decoration: InputDecoration(
                      hintText: 'Search venue by name, location, or sport',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (filteredRows.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                _statusFilter == 'archived'
                    ? 'No archived venues found.'
                    : _statusFilter == 'active'
                        ? 'No active venues found.'
                        : 'No venues found.',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              ),
            );
          }

          final item = filteredRows[index - 1];
          final isProcessing = _processingFacilityId == item.id;
          final isArchived = item.archivedAt != null || !item.isActive;
          final isHighlighted = _highlightedFacilityId == item.id;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isHighlighted ? const Color(0xFFFFFBEB) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB)),
            ),
            child: ListTile(
              tileColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide.none,
              ),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                isArchived
                    ? '${item.locationName} • ${item.sportType.toUpperCase()} • ARCHIVED'
                    : '${item.locationName} • ${item.sportType.toUpperCase()}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF111827), Color(0xFF1F2937)]),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '\$${item.basePricePerHour.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: (isProcessing || isArchived) ? null : () => _updateVenuePrice(item),
                    tooltip: 'Edit Price',
                    icon: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: (isProcessing || isArchived) ? null : () => _editVenueDetails(item),
                    tooltip: 'Edit Venue Details',
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  IconButton(
                    onPressed: isProcessing
                        ? null
                        : () => (isArchived ? _restoreVenue(item) : _archiveVenue(item)),
                    tooltip: isArchived ? 'Restore Venue' : 'Archive Venue',
                    icon: Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemCount: (filteredRows.isEmpty ? 1 : filteredRows.length) + 1,
      );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _OwnerHeroCard extends StatelessWidget {
  const _OwnerHeroCard({required this.ownerEmail});

  final String ownerEmail;

  @override
  Widget build(BuildContext context) {
    final name = ownerEmail.split('@').first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1320), Color(0xFF2A3342)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.monitor_heart_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $name',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Track bookings, revenue, and venue activity in one friendly dashboard.',
                  style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueMiniTrend extends StatelessWidget {
  const _RevenueMiniTrend({
    required this.bookings,
    required this.days,
    required this.title,
  });

  final List<BookingItem> bookings;
  final int days;
  final String title;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chartDays = List<DateTime>.generate(days, (index) => today.subtract(Duration(days: days - 1 - index)));

    final totals = <double>[];
    for (final day in chartDays) {
      final next = day.add(const Duration(days: 1));
      final total = bookings
          .where((b) => b.startAt.isAfter(day) && b.startAt.isBefore(next) && b.paymentStatus == 'mock_paid')
          .fold<double>(0, (sum, row) => sum + row.finalPrice);
      totals.add(total);
    }

    final maxVal = totals.fold<double>(0, (max, value) => value > max ? value : max);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(chartDays.length, (index) {
              final value = totals[index];
              final ratio = maxVal <= 0 ? 0.08 : (value / maxVal).clamp(0.08, 1.0);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == chartDays.length - 1 ? 0 : 6),
                  child: Column(
                    children: [
                      Container(
                        height: 90 * ratio,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(DateFormat('E').format(chartDays[index]), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TopVenueAndOccupancyCard extends StatelessWidget {
  const _TopVenueAndOccupancyCard({
    required this.topVenueName,
    required this.topVenueRevenue,
    required this.occupancyRate,
    required this.rangeLabel,
  });

  final String topVenueName;
  final double topVenueRevenue;
  final double occupancyRate;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance Snapshot', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  topVenueName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text('\$${topVenueRevenue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Estimated Occupancy ($rangeLabel)', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: occupancyRate / 100,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF0F766E)),
            ),
          ),
          const SizedBox(height: 6),
          Text('${occupancyRate.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _CouponPerformanceCard extends StatelessWidget {
  const _CouponPerformanceCard({
    required this.couponStats,
    required this.rangeLabel,
  });

  final List<MapEntry<String, ({int uses, double savings, double revenue})>> couponStats;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Coupon Performance',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            'Top coupons for $rangeLabel by redemptions and savings',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (couponStats.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'No coupon usage in this range yet.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              ),
            )
          else
            ...couponStats.take(5).map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value.uses} uses',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Saved \$${entry.value.savings.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _OwnerBookingHistoryCard extends StatelessWidget {
  const _OwnerBookingHistoryCard({required this.item});

  final BookingItem item;

  @override
  Widget build(BuildContext context) {
    final statusLower = item.status.toLowerCase();
    final isConfirmed = statusLower == 'confirmed';
    final statusColor = isConfirmed ? const Color(0xFF047857) : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.facilityName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status.toUpperCase(),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 460 ? 1 : 2;
              return GridView.count(
                crossAxisCount: cols,
                childAspectRatio: cols == 1 ? 4.8 : 3.1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: [
                  _HistoryMeta(label: 'Booking ID', value: '#${item.id}'),
                  _HistoryMeta(label: 'Amount', value: '\$${item.finalPrice.toStringAsFixed(2)}', highlight: true),
                  _HistoryMeta(label: 'Start', value: DateFormat('EEE, dd MMM HH:mm').format(item.startAt)),
                  _HistoryMeta(label: 'End', value: DateFormat('EEE, dd MMM HH:mm').format(item.endAt)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryMeta extends StatelessWidget {
  const _HistoryMeta({required this.label, required this.value, this.highlight = false});

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
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingBlock extends StatelessWidget {
  const _DashboardLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
