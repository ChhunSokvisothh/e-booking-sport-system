import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../booking/booking_providers.dart';
import '../facility/facility_providers.dart';

class OwnerCouponScreen extends ConsumerStatefulWidget {
  const OwnerCouponScreen({super.key});

  @override
  ConsumerState<OwnerCouponScreen> createState() => _OwnerCouponScreenState();
}

class _OwnerCouponScreenState extends ConsumerState<OwnerCouponScreen> {
  final _codeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '10');

  DateTime _startsAt = DateTime.now();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;
  int? _processingCouponId;
  List<CouponItem>? _couponRows;
  int? _highlightedCouponId;

  void _flashCouponRow(int couponId) {
    setState(() => _highlightedCouponId = couponId);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _highlightedCouponId != couponId) {
        return;
      }
      setState(() => _highlightedCouponId = null);
    });
  }

  CouponItem? _couponFromResponse(Map<String, dynamic> response) {
    final raw = response['coupon'];
    if (raw is Map<String, dynamic>) {
      return CouponItem.fromJson(raw);
    }
    if (raw is Map) {
      return CouponItem.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  void _upsertCoupon(CouponItem coupon) {
    final source = List<CouponItem>.from(_couponRows ?? const <CouponItem>[]);
    final idx = source.indexWhere((row) => row.id == coupon.id);
    if (idx >= 0) {
      source[idx] = coupon;
    } else {
      source.insert(0, coupon);
    }
    source.sort((a, b) => b.id.compareTo(a.id));
    setState(() => _couponRows = source);
    _flashCouponRow(coupon.id);
  }

  void _invalidateRelatedCouponProviders() {
    ref.invalidate(ownerCouponsProvider);
    ref.invalidate(activeCouponsProvider);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initial,
    );
    if (pickedDate == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) {
      return;
    }

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startsAt = dt;
      } else {
        _endsAt = dt;
      }
    });
  }

  Future<void> _saveCoupon() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final code = _codeCtrl.text.trim().toUpperCase();
    final discount = double.tryParse(_discountCtrl.text.trim());

    if (code.isEmpty || discount == null || discount <= 0 || discount > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid code and discount (1-100).')),
      );
      return;
    }

    if (!_endsAt.isAfter(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after start date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.postJson(
        '/api/coupons/owner/',
        {
          'code': code,
          'title': _titleCtrl.text.trim(),
          'description': _descriptionCtrl.text.trim(),
          'discount_percent': discount,
          'starts_at': _startsAt.toIso8601String(),
          'ends_at': _endsAt.toIso8601String(),
        },
        token: session.token,
      );
      final coupon = _couponFromResponse(response);
      if (coupon != null) {
        _upsertCoupon(coupon);
      }
      _invalidateRelatedCouponProviders();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coupon saved successfully.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save coupon right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _toggleCoupon(int couponId, bool isActive) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    setState(() => _processingCouponId = couponId);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.patchJson('/api/coupons/owner/$couponId/', {'is_active': isActive}, token: session.token);
      final coupon = _couponFromResponse(response);
      if (coupon != null) {
        _upsertCoupon(coupon);
      }
      _invalidateRelatedCouponProviders();
    } finally {
      if (mounted) {
        setState(() => _processingCouponId = null);
      }
    }
  }

  Future<void> _deleteCoupon(int couponId) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete coupon?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    setState(() => _processingCouponId = couponId);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.deleteJson('/api/coupons/owner/$couponId/', token: session.token);
      final coupon = _couponFromResponse(response);
      if (coupon != null) {
        _upsertCoupon(coupon);
      }
      _invalidateRelatedCouponProviders();
    } finally {
      if (mounted) {
        setState(() => _processingCouponId = null);
      }
    }
  }

  Widget _buildCouponsList(List<CouponItem> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No coupons yet.'),
      );
    }

    return Column(
      children: rows
          .map(
            (coupon) {
              final isHighlighted = _highlightedCouponId == coupon.id;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isHighlighted ? const Color(0xFFFFFBEB) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${coupon.code} • ${coupon.discountPercent.toStringAsFixed(0)}%',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                coupon.description.isEmpty ? 'No description' : coupon.description,
                                style: const TextStyle(color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${DateFormat('dd MMM yyyy').format(coupon.startsAt)} - ${DateFormat('dd MMM yyyy').format(coupon.endsAt)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: coupon.isCurrentlyValid ? const Color(0xFFECFDF5) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            coupon.isCurrentlyValid ? 'Active' : 'Inactive',
                            style: TextStyle(
                              color: coupon.isCurrentlyValid ? const Color(0xFF047857) : const Color(0xFF991B1B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _processingCouponId == coupon.id ? null : () => _toggleCoupon(coupon.id, !coupon.isActive),
                          icon: const Icon(Icons.toggle_on_outlined),
                          label: Text(coupon.isActive ? 'Deactivate' : 'Activate'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _processingCouponId == coupon.id ? null : () => _deleteCoupon(coupon.id),
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                          label: const Text('Delete', style: TextStyle(color: Color(0xFFB91C1C))),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final couponsAsync = ref.watch(ownerCouponsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Coupon Management')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Create time-limited coupons for checkout discounts.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create / Update Coupon', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'Code (e.g. NEWUSER50)')),
                const SizedBox(height: 8),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 8),
                TextField(controller: _descriptionCtrl, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                TextField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Discount %'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDateTime(isStart: true),
                        icon: const Icon(Icons.event),
                        label: Text('Start: ${DateFormat('dd MMM HH:mm').format(_startsAt)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDateTime(isStart: false),
                        icon: const Icon(Icons.event_available),
                        label: Text('End: ${DateFormat('dd MMM HH:mm').format(_endsAt)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveCoupon,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Coupon'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Created Coupons', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          couponsAsync.when(
            loading: () {
              if (_couponRows != null) {
                return _buildCouponsList(_couponRows!);
              }
              return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
            },
            error: (error, stack) {
              if (_couponRows != null) {
                return _buildCouponsList(_couponRows!);
              }
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Unable to load coupons.'),
              );
            },
            data: (rows) {
              _couponRows = List<CouponItem>.from(rows);
              return _buildCouponsList(_couponRows!);
            },
          ),
        ],
      ),
    );
  }
}
