import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import '../../core/models.dart';
import '../../core/sport_visuals.dart';
import '../facility/facility_providers.dart';
import 'booking_providers.dart';
import 'mock_payment_screen.dart';

class QuickBookScreen extends ConsumerStatefulWidget {
  const QuickBookScreen({
    super.key,
    required this.onOpenDashboard,
    this.initialSlot,
    this.initialSlots,
    this.initialSportType,
    this.initialFacilityId,
  });

  final VoidCallback onOpenDashboard;
  final LiveSlotAvailability? initialSlot;
  final List<LiveSlotAvailability>? initialSlots;
  final String? initialSportType;
  final String? initialFacilityId;

  @override
  ConsumerState<QuickBookScreen> createState() => _QuickBookScreenState();
}

class _QuickBookScreenState extends ConsumerState<QuickBookScreen> {
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _indoorOnly = false;
  String? _sportType;
  String? _selectedFacilityId;
  final Set<String> _selectedSlotIds = <String>{};
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _sportType = widget.initialSportType;
    _selectedFacilityId = widget.initialFacilityId;
    final initialSlots = widget.initialSlots;

    if (initialSlots != null && initialSlots.isNotEmpty) {
      final first = initialSlots.first;
      _selectedDate = DateTime(first.startAt.year, first.startAt.month, first.startAt.day);
      _sportType = first.sportType;
      _selectedFacilityId = first.facilityId;
      return;
    }

    final initial = widget.initialSlot;
    if (initial == null) {
      return;
    }

    _selectedDate = DateTime(initial.startAt.year, initial.startAt.month, initial.startAt.day);
    _sportType = initial.sportType;
    _selectedFacilityId = initial.facilityId;
    if (initial.startAt.isAfter(now)) {
      _selectedSlotIds.add(initial.slotId);
    }
  }

  _SlotVisualState _slotVisualState({
    required bool isPast,
    required bool isAvailable,
    required bool bookedByMe,
    required bool isOpen,
    required bool selected,
  }) {
    if (bookedByMe) {
      return _SlotVisualState.bookedByMe;
    }
    if (selected) {
      return _SlotVisualState.selected;
    }
    if (isPast || !isAvailable || !isOpen) {
      return _SlotVisualState.unavailable;
    }
    return _SlotVisualState.available;
  }

  Map<String, String> _buildQuery() {
    final formatter = DateFormat('yyyy-MM-dd');
    return {
      'date': formatter.format(_selectedDate),
      ...?_sportType == null ? null : {'sport_type': _sportType!},
      ...?_selectedFacilityId == null ? null : {'facility_id': _selectedFacilityId!},
      ...?_indoorOnly ? {'is_indoor': 'true'} : null,
    };
  }

  Future<int> _createPendingBooking(ApiClient api, String token, LiveSlotAvailability slot) async {
    final basePrice = slot.basePricePerHour;
    final suggestion = {
      'option_id': '${slot.facilityId}:${slot.slotId}:1',
      'facility_name': slot.facilityName,
      'start_at': slot.startAt.toIso8601String(),
      'duration_hours': 1,
      'base_price': basePrice.toStringAsFixed(2),
      'weather_discount': '0.00',
      'empty_slot_discount': '0.00',
      'final_price': basePrice.toStringAsFixed(2),
      'currency': 'USD',
      'rain_mm': 0,
    };

    final result = await api.postJson(
      '/api/chat/',
      {
        'message': 'confirm',
        'booking_source': 'manual',
        'selected_option_id': suggestion['option_id'],
        'suggestions': [suggestion],
      },
      token: token,
    );

    final bookingId = result['booking_id'] as int?;
    if (bookingId == null) {
      throw Exception('Booking was not created.');
    }
    return bookingId;
  }

  Future<void> _bookSelectedSlots(List<LiveSlotAvailability> selectedSlots) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first.')),
      );
      return;
    }

    final sorted = [...selectedSlots]..sort((a, b) => a.startAt.compareTo(b.startAt));
    final first = sorted.first;
    final last = sorted.last;
    final total = sorted.fold<double>(0, (sum, slot) => sum + slot.basePricePerHour);

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Confirm Booking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                const SizedBox(height: 8),
                Text(first.facilityName, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE, dd MMM').format(first.startAt)} • ${DateFormat('HH:mm').format(first.startAt)} - ${DateFormat('HH:mm').format(last.endAt)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text('${sorted.length} hour slot(s) selected'),
                const SizedBox(height: 6),
                Text('Total: \$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _processing = true);

    try {
      final api = ref.read(apiClientProvider);
      final bookingIds = <int>[];
      for (final slot in sorted) {
        final id = await _createPendingBooking(api, session.token, slot);
        bookingIds.add(id);
      }

      if (!mounted) {
        return;
      }

      final paymentResult = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => MockPaymentScreen(
            bookingIds: bookingIds,
            facilityName: first.facilityName,
            startAt: first.startAt,
            endAt: last.endAt,
            totalPrice: total,
            totalHours: sorted.length.toDouble(),
          ),
        ),
      );

      if (paymentResult == true && mounted) {
        ref.invalidate(bookingHistoryProvider);
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(liveSlotAvailabilityProvider);
        ref.invalidate(liveSlotAvailabilityWithDiagnosticsProvider(serializeQuery(_buildQuery())));
        await Future.wait([
          ref.read(bookingHistoryProvider.future),
          ref.read(dashboardSummaryProvider.future),
        ]);
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
      }

      if (paymentResult == 'refresh_slots' && mounted) {
        ref.invalidate(bookingHistoryProvider);
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(liveSlotAvailabilityProvider);
        ref.invalidate(liveSlotAvailabilityWithDiagnosticsProvider(serializeQuery(_buildQuery())));
        await Future.wait([
          ref.read(bookingHistoryProvider.future),
          ref.read(dashboardSummaryProvider.future),
        ]);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not complete your booking. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;
    final tiny = width < 360;
    final queryKey = serializeQuery(_buildQuery());
    final slotsAsync = ref.watch(liveSlotAvailabilityWithDiagnosticsProvider(queryKey));
    final sports = [null, ...SportVisuals.all.map((e) => e.sportType)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Booking'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                final now = DateTime.now();
                _selectedDate = DateTime(now.year, now.month, now.day);
                _sportType = null;
                _indoorOnly = false;
                _selectedFacilityId = null;
                _selectedSlotIds.clear();
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FAFB), Color(0xFFEDEFF2)],
          ),
        ),
        child: slotsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: OutlinedButton.icon(
                onPressed: () => ref.invalidate(liveSlotAvailabilityWithDiagnosticsProvider(queryKey)),
                icon: const Icon(Icons.refresh),
                label: const Text('Unable to load slots. Try Again'),
              ),
            ),
          ),
          data: (payload) {
            final now = DateTime.now();
            final allRows = payload.data;
            final dateRows = allRows.where((row) {
              final d = row.startAt;
              return d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
            }).toList()
              ..sort((a, b) => a.startAt.compareTo(b.startAt));

            final facilityIds = <String>{};
            final facilities = <LiveSlotAvailability>[];
            for (final row in dateRows) {
              if (facilityIds.add(row.facilityId)) {
                facilities.add(row);
              }
            }

            final selectedFacilityId = (_selectedFacilityId != null && facilityIds.contains(_selectedFacilityId))
                ? _selectedFacilityId
                : (facilities.isEmpty ? null : facilities.first.facilityId);

            final selectedFacilityRows = dateRows
                .where((row) => row.facilityId == selectedFacilityId)
                .toList()
              ..sort((a, b) => a.startAt.compareTo(b.startAt));

            final validSlotIds = selectedFacilityRows.map((e) => e.slotId).toSet();
            final effectiveSelectedIds = _selectedSlotIds.where(validSlotIds.contains).toSet();

            final selectedSlots = selectedFacilityRows.where((row) => effectiveSelectedIds.contains(row.slotId)).toList()
              ..sort((a, b) => a.startAt.compareTo(b.startAt));

            final isBilliard = _sportType == 'billiard';
            final resourceTitle = isBilliard ? 'Select Table' : 'Select Field';

            final total = selectedSlots.fold<double>(0, (sum, slot) => sum + slot.basePricePerHour);

            return ListView(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 10, compact ? 12 : 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF334155)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Plan Your Match',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedSlots.isEmpty
                            ? 'Choose one or multiple hours'
                            : '${selectedSlots.length} slot(s) selected • \$${total.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _sportType,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: sports
                                .map(
                                  (sport) => DropdownMenuItem<String?>(
                                    value: sport,
                                    child: Text(
                                      SportVisuals.of(sport).label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (sport) {
                              setState(() {
                                _sportType = sport;
                                _selectedFacilityId = null;
                                _selectedSlotIds.clear();
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  value: _indoorOnly,
                  onChanged: (value) => setState(() => _indoorOnly = value),
                  dense: tiny,
                  title: Text(
                    'Indoor only',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: tiny ? 14 : null),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 6),
                _SectionTitle(title: 'Select Date', tiny: tiny),
                const SizedBox(height: 10),
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final base = DateTime.now();
                      final d = DateTime(base.year, base.month, base.day).add(Duration(days: index));
                      final isSelected = d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
                      return _DateChip(
                        date: d,
                        isSelected: isSelected,
                        tiny: tiny,
                        onTap: () {
                          setState(() {
                            _selectedDate = DateTime(d.year, d.month, d.day);
                            _selectedFacilityId = null;
                            _selectedSlotIds.clear();
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: resourceTitle, tiny: tiny),
                const SizedBox(height: 10),
                if (facilities.isEmpty)
                  const Text('No fields/tables available for this date.')
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: facilities.map((facilityRow) {
                      final selected = facilityRow.facilityId == selectedFacilityId;
                      return ChoiceChip(
                        label: Text(facilityRow.facilityName),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: const Color(0xFF111827),
                        labelStyle: TextStyle(color: selected ? Colors.white : const Color(0xFF4B5563), fontWeight: FontWeight.w700),
                        onSelected: (_) {
                          setState(() {
                            _selectedFacilityId = facilityRow.facilityId;
                            _selectedSlotIds.clear();
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 18),
                  _SectionTitle(title: 'Select Time (Multi-select)', tiny: tiny),
                const SizedBox(height: 10),
                if (selectedFacilityRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No time slots for this date. Try another date or sport.'),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = math.max(2, (constraints.maxWidth / (compact ? 118 : 136)).floor());
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: selectedFacilityRows.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: compact ? 2.4 : 2.7,
                        ),
                        itemBuilder: (context, index) {
                          final slot = selectedFacilityRows[index];
                          final isPast = slot.startAt.isBefore(now);
                          final selected = effectiveSelectedIds.contains(slot.slotId);
                          final state = _slotVisualState(
                            isPast: isPast,
                            isAvailable: slot.isAvailable,
                            bookedByMe: slot.bookedByMe,
                            isOpen: slot.isOpen,
                            selected: selected,
                          );
                          return _TimeChip(
                            label: DateFormat('HH:mm').format(slot.startAt),
                            state: state,
                            onTap: () {
                              if (state == _SlotVisualState.unavailable || state == _SlotVisualState.bookedByMe) {
                                return;
                              }
                              setState(() {
                                if (selected) {
                                  _selectedSlotIds.remove(slot.slotId);
                                } else {
                                  _selectedSlotIds.add(slot.slotId);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                const SizedBox(height: 16),
                if (selectedSlots.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedSlots.first.facilityName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('EEE, dd MMM').format(selectedSlots.first.startAt)} • ${DateFormat('HH:mm').format(selectedSlots.first.startAt)} - ${DateFormat('HH:mm').format(selectedSlots.last.endAt)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${selectedSlots.length} hour slot(s) • Total \$${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                if (selectedSlots.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedSlots.map((slot) {
                      return InputChip(
                        label: Text(DateFormat('HH:mm').format(slot.startAt)),
                        selected: true,
                        showCheckmark: false,
                        selectedColor: const Color(0xFFFFFBEB),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        onDeleted: () {
                          setState(() => _selectedSlotIds.remove(slot.slotId));
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: const [
                    _TimelineLegendDot(color: Color(0xFFB91C1C), label: 'Unavailable / full'),
                    _TimelineLegendDot(color: Color(0xFF0F766E), label: 'Available'),
                    _TimelineLegendDot(color: Color(0xFFF59E0B), label: 'Selected'),
                    _TimelineLegendDot(color: Color(0xFF2563EB), label: 'Booked by me'),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _processing || selectedSlots.isEmpty
                      ? null
                      : () => _bookSelectedSlots(selectedSlots),
                  icon: _processing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.flash_on),
                  label: Text(_processing ? 'Processing...' : 'Book Selected Slots'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                      return;
                    }
                    widget.onOpenDashboard();
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Back to Home'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TimelineLegendDot extends StatelessWidget {
  const _TimelineLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.tiny = false});

  final String title;
  final bool tiny;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Color(0xFF6B7280),
        fontWeight: FontWeight.w800,
        fontSize: tiny ? 16 : 18,
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.isSelected,
    this.tiny = false,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final bool tiny;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('E').format(date);
    final num = DateFormat('d').format(date);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: tiny ? 62 : 70,
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)])
              : const LinearGradient(colors: [Color(0xFFF8FAFC), Color(0xFFE5E7EB)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF334155) : const Color(0xFFD1D5DB),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              num,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: tiny ? 24 : 28,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _SlotVisualState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = state == _SlotVisualState.unavailable || state == _SlotVisualState.bookedByMe;

    final Decoration decoration;
    final Color textColor;
    switch (state) {
      case _SlotVisualState.available:
        decoration = BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF10B981), width: 1.4),
        );
        textColor = const Color(0xFF065F46);
        break;
      case _SlotVisualState.selected:
        decoration = BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        );
        textColor = const Color(0xFF92400E);
        break;
      case _SlotVisualState.unavailable:
        decoration = BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
        );
        textColor = const Color(0xFF991B1B);
        break;
      case _SlotVisualState.bookedByMe:
        decoration = BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1D4ED8), width: 1.4),
        );
        textColor = Colors.white;
        break;
    }

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: decoration,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey<String>('${state.name}_$label'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state == _SlotVisualState.selected) ...[
                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF92400E)),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _SlotVisualState { available, selected, unavailable, bookedByMe }
