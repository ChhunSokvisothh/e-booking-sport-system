import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/data/auth_session.dart';
import '../../shared/models/models.dart';
import '../facility/facility_providers.dart';
import 'booking_providers.dart';
import 'payment_method_selector.dart';

class MockPaymentScreen extends ConsumerStatefulWidget {
  const MockPaymentScreen({
    super.key,
    this.bookingId,
    this.bookingIds = const [],
    this.facilityId,
    this.chatOption,
    this.paymentQuote,
    this.bookingSource,
    this.chatbotSessionId,
    this.facilityName,
    this.courtNumber,
    this.courtLabel,
    this.startAt,
    this.endAt,
    this.totalPrice,
    this.totalHours,
    this.currency = 'USD',
  });

  final int? bookingId;
  final List<int> bookingIds;
  final int? facilityId;
  final Map<String, dynamic>? chatOption;
  final Map<String, dynamic>? paymentQuote;
  final String? bookingSource;
  final String? chatbotSessionId;
  final String? facilityName;
  final int? courtNumber;
  final String? courtLabel;
  final DateTime? startAt;
  final DateTime? endAt;
  final double? totalPrice;
  final double? totalHours;
  final String currency;

  @override
  ConsumerState<MockPaymentScreen> createState() => _MockPaymentScreenState();
}

class _MockPaymentScreenState extends ConsumerState<MockPaymentScreen> {
  static const Duration _paymentWindow = Duration(minutes: 5);
  bool _loading = false;
  bool _expiredHandled = false;
  Timer? _countdownTimer;
  late DateTime _expiresAt;
  Duration _remaining = _paymentWindow;
  final List<PaymentMethodOption> _methods = standardPaymentMethods;
  int _selectedMethod = 0;
  final TextEditingController _couponCodeCtrl = TextEditingController();
  CouponItem? _appliedCoupon;
  bool _applyingCoupon = false;

  @override
  void initState() {
    super.initState();
    _expiresAt = DateTime.now().add(_paymentWindow);
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _couponCodeCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final diff = _expiresAt.difference(DateTime.now());
      if (diff <= Duration.zero) {
        setState(() => _remaining = Duration.zero);
        _countdownTimer?.cancel();
        _handlePaymentTimeout();
      } else {
        setState(() => _remaining = diff);
      }
    });
  }

  String get _remainingLabel {
    final totalSeconds = _remaining.inSeconds < 0 ? 0 : _remaining.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _handlePaymentTimeout() async {
    if (_expiredHandled) {
      return;
    }
    _expiredHandled = true;

    final api = ref.read(apiClientProvider);
    final session = ref.read(authSessionProvider);
    if (session != null) {
      for (final id in _effectiveBookingIds) {
        try {
          await api.postJson('/api/bookings/$id/cancel/', {}, token: session.token);
        } catch (_) {
          // Ignore cleanup failures; backend periodic expiry also restores state.
        }
      }
    }

    ref.invalidate(bookingHistoryProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(liveSlotAvailabilityProvider);
    await Future.wait([
      ref.read(bookingHistoryProvider.future),
      ref.read(dashboardSummaryProvider.future),
    ]);

    if (!mounted) {
      return;
    }
    final action = await _showPaymentExpiredDialog();
    if (!mounted) {
      return;
    }
    if (action == 'refresh_slots') {
      Navigator.pop(context, 'refresh_slots');
      return;
    }
    Navigator.pop(context, false);
  }

  Future<String?> _showPaymentExpiredDialog() async {
    if (!mounted) {
      return null;
    }
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Payment Time Expired'),
          content: const Text(
            'Your 5-minute payment window has ended. The booking was reset and slots are available again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('close'),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop('refresh_slots'),
              icon: const Icon(Icons.refresh),
              label: const Text('Find Slots Again'),
            ),
          ],
        );
      },
    );
  }

  void _handleCouponTextChanged(String value) {
    final applied = _appliedCoupon;
    if (applied != null && value.trim().toUpperCase() != applied.code) {
      setState(() => _appliedCoupon = null);
    }
  }

  Future<void> _applyCouponCode() async {
    final code = _couponCodeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a coupon code first.')),
      );
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again to validate this coupon.')),
      );
      return;
    }

    setState(() => _applyingCoupon = true);
    try {
      final query = <String, String>{'code': code};
      final facilityId = _effectiveFacilityId;
      if (facilityId != null) {
        query['facility_id'] = facilityId.toString();
      }

      final rows = await ref.read(apiClientProvider).getList(
        '/api/coupons/active/',
        query,
        session.token,
      );
      if (rows.isEmpty) {
        throw Exception(
          'Coupon is invalid for this venue, inactive, expired, or not found.',
        );
      }

      final coupon = CouponItem.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
      if (!mounted) return;
      setState(() {
        _appliedCoupon = coupon;
        _couponCodeCtrl.text = coupon.code;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${coupon.code} applied — ${coupon.discountPercent.toStringAsFixed(0)}% off.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  double _discountAmount(double total) {
    final coupon = _appliedCoupon;
    if (coupon == null) {
      return 0;
    }
    return total * (coupon.discountPercent / 100);
  }

  List<int> get _effectiveBookingIds {
    return widget.bookingIds.isNotEmpty
        ? widget.bookingIds
        : (widget.bookingId == null ? const <int>[] : <int>[widget.bookingId!]);
  }

  int? get _effectiveFacilityId {
    if (widget.facilityId != null) {
      return widget.facilityId;
    }

    final rawFacilityId = widget.chatOption?['facility_id'];
    if (rawFacilityId is num) {
      return rawFacilityId.toInt();
    }
    final parsed = int.tryParse(rawFacilityId?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }

    final optionId = widget.chatOption?['option_id']?.toString() ?? '';
    return int.tryParse(optionId.split(':').first);
  }

  String get _receiptId {
    final datePart = DateFormat('yyyyMMdd').format(DateTime.now());
    String first = '0000';
    if (_effectiveBookingIds.isNotEmpty) {
      first = _effectiveBookingIds.first.toString().padLeft(4, '0');
    } else {
      final optionId = widget.chatOption?['option_id']?.toString() ?? '';
      final chunks = optionId.split('_');
      if (chunks.length >= 2) {
        first = chunks[1].padLeft(4, '0');
      }
    }
    return 'RCPT-$datePart-$first';
  }

  String get _qrPayload {
    return jsonEncode({
      'receipt_id': _receiptId,
      'booking_ids': _effectiveBookingIds,
      'facility': widget.facilityName,
      'court_number': widget.courtNumber,
      'court_label': widget.courtLabel,
      'start_at': widget.startAt?.toIso8601String(),
      'end_at': widget.endAt?.toIso8601String(),
      'amount': ((widget.totalPrice ?? 0) - _discountAmount(widget.totalPrice ?? 0))
          .clamp(0, double.infinity)
          .toStringAsFixed(2),
      'coupon_code': _appliedCoupon?.code,
      'currency': widget.currency,
    });
  }

  Future<void> _simulatePay() async {
    if (_remaining <= Duration.zero) {
      await _handlePaymentTimeout();
      return;
    }
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final session = ref.read(authSessionProvider);
    if (session == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first.')),
        );
      }
      return;
    }

    try {
      final ids = _effectiveBookingIds;
      final originalTotal = widget.totalPrice ?? 0;
      final discountAmount = _discountAmount(originalTotal);
      final totalAfterDiscount = (originalTotal - discountAmount).clamp(0, double.infinity).toDouble();

      if (ids.isEmpty && (widget.chatOption == null || widget.chatOption!.isEmpty)) {
        throw Exception('No booking or chat option provided');
      }

      final payload = <String, dynamic>{
        'payment_channel': _methods[_selectedMethod].channel,
        'payment_provider': _methods[_selectedMethod].provider,
        if (_appliedCoupon != null) 'coupon_code': _appliedCoupon!.code,
      };

      if (ids.isNotEmpty) {
        if (ids.length == 1) {
          payload['booking_id'] = ids.first;
        } else {
          payload['booking_ids'] = ids;
        }
      } else {
        payload['chat_option'] = widget.chatOption;
        payload['payment_quote'] = widget.paymentQuote;
        payload['amount'] = totalAfterDiscount.toStringAsFixed(2);
        payload['booking_source'] = widget.bookingSource ?? 'chatbot';
        if (widget.chatbotSessionId != null && widget.chatbotSessionId!.isNotEmpty) {
          payload['chatbot_session_id'] = widget.chatbotSessionId;
        }
      }

      await api.postJson('/api/mock-payment/', payload, token: session.token);

      _countdownTimer?.cancel();

      ref.invalidate(bookingHistoryProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(liveSlotAvailabilityProvider);
      if (mounted) {
        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierLabel: 'payment-success',
          barrierColor: Colors.black.withValues(alpha: 0.32),
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (dialogContext, _, _) {
            return _PaymentSuccessDialog(
              title: 'Payment Successful',
              message: 'Your booking is confirmed and receipt is ready. Good luck and enjoy your game!',
              onGoHome: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            );
          },
          transitionBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: Tween<double>(begin: 0.88, end: 1).animate(curve), child: child),
            );
          },
        );
        if (!mounted) {
          return;
        }
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        final raw = error.toString().replaceFirst('Exception: ', '').trim();
        if (raw.toLowerCase().contains('payment window expired')) {
          await _handlePaymentTimeout();
          return;
        }
        final couponMessage = raw.toLowerCase().contains('coupon') ? raw : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(couponMessage ?? 'Payment could not be completed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _effectiveBookingIds;
    final bookingLabel = ids.isEmpty ? 'AI quote' : (ids.length == 1 ? '#${ids.first}' : '${ids.length} bookings');
    final hasReceipt = widget.facilityName != null && widget.startAt != null && widget.endAt != null && widget.totalPrice != null;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    final tiny = width < 360;
    final originalTotal = widget.totalPrice ?? 0;
    final discountAmount = _discountAmount(originalTotal);
    final totalAfterDiscount = (originalTotal - discountAmount).clamp(0, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Secure Checkout')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 18),
              child: Column(
                children: [
                  _CheckoutHeader(bookingLabel: bookingLabel),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Color(0xFF92400E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Complete payment in $_remainingLabel (limit 5:00).',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF78350F)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasReceipt)
                    _ReceiptCard(
                      facilityName: widget.facilityName!,
                      courtNumber: widget.courtNumber,
                      courtLabel: widget.courtLabel,
                      startAt: widget.startAt!,
                      endAt: widget.endAt!,
                      totalPrice: totalAfterDiscount,
                      currency: widget.currency,
                      totalHours: widget.totalHours,
                      bookingLabel: bookingLabel,
                      bookingIds: ids,
                      receiptId: _receiptId,
                      qrPayload: _qrPayload,
                    ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Apply Coupon', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (compact)
                          Column(
                            children: [
                              TextField(
                                controller: _couponCodeCtrl,
                                textCapitalization: TextCapitalization.characters,
                                onChanged: _handleCouponTextChanged,
                                decoration: InputDecoration(
                                  hintText: 'Enter coupon code',
                                  suffixIcon: _appliedCoupon == null
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () => setState(() {
                                            _appliedCoupon = null;
                                            _couponCodeCtrl.clear();
                                          }),
                                        ),
                                ),
                                onSubmitted: (_) => _applyCouponCode(),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _applyingCoupon ? null : _applyCouponCode,
                                  icon: _applyingCoupon
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sell_outlined),
                                  label: Text(_applyingCoupon ? 'Checking...' : 'Apply Code'),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _couponCodeCtrl,
                                  textCapitalization: TextCapitalization.characters,
                                  onChanged: _handleCouponTextChanged,
                                  decoration: InputDecoration(
                                    hintText: 'Enter coupon code',
                                    suffixIcon: _appliedCoupon == null
                                        ? null
                                        : IconButton(
                                            icon: const Icon(Icons.close),
                                            onPressed: () => setState(() {
                                              _appliedCoupon = null;
                                              _couponCodeCtrl.clear();
                                            }),
                                          ),
                                  ),
                                  onSubmitted: (_) => _applyCouponCode(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _applyingCoupon ? null : _applyCouponCode,
                                icon: _applyingCoupon
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sell_outlined),
                                label: Text(_applyingCoupon ? 'Checking...' : 'Apply Code'),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter the coupon code provided by this venue, then tap Apply Code.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_appliedCoupon != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFEFF6FF), Color(0xFFEEF2FF)]),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.local_offer, color: Color(0xFF1D4ED8), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Coupon applied: ${_appliedCoupon!.code} (${_appliedCoupon!.discountPercent.toStringAsFixed(0)}%)',
                                    maxLines: tiny ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF1E3A8A),
                                      fontSize: tiny ? 12.5 : 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Subtotal: ${originalTotal.toStringAsFixed(2)} ${widget.currency}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('Discount: -${discountAmount.toStringAsFixed(2)} ${widget.currency}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857))),
                              Text('Total: ${totalAfterDiscount.toStringAsFixed(2)} ${widget.currency}', style: const TextStyle(fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(tiny ? 10 : 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF8FAFC), Color(0xFFEAF2FF)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: PaymentMethodSelector(
                      methods: _methods,
                      selectedIndex: _selectedMethod,
                      compact: tiny,
                      onSelected: (index) => setState(() => _selectedMethod = index),
                    ),

                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _simulatePay,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.credit_score),
                      label: Text(_loading ? 'Processing...' : (tiny ? 'Pay Now' : 'Simulate Payment Success')),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: tiny ? 12 : 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CheckoutHeader extends StatelessWidget {
  const _CheckoutHeader({required this.bookingLabel});

  final String bookingLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 360;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(tiny ? 12 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF334155)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking $bookingLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (tiny ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.titleLarge)?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              SizedBox(height: tiny ? 4 : 6),
              Text(
                'Secure checkout is ready. Confirm now to lock your slot and issue your receipt.',
                style: TextStyle(
                  color: const Color(0xFFE2E8F0),
                  fontSize: tiny ? 12.5 : 14,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.facilityName,
    this.courtNumber,
    this.courtLabel,
    required this.startAt,
    required this.endAt,
    required this.totalPrice,
    required this.currency,
    required this.totalHours,
    required this.bookingLabel,
    required this.bookingIds,
    required this.receiptId,
    required this.qrPayload,
  });

  final String facilityName;
  final int? courtNumber;
  final String? courtLabel;
  final DateTime startAt;
  final DateTime endAt;
  final double totalPrice;
  final String currency;
  final double? totalHours;
  final String bookingLabel;
  final List<int> bookingIds;
  final String receiptId;
  final String qrPayload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              'https://images.unsplash.com/photo-1517649763962-0c623066013b?auto=format&fit=crop&w=1200&q=70',
              height: 64,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 64,
                color: const Color(0xFFE5E7EB),
                alignment: Alignment.center,
                child: const Icon(Icons.receipt_long),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Receipt Preview', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF115E59)]),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  receiptId,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 430 ? 1 : 2;
              return GridView.count(
                crossAxisCount: cols,
                // Wide desktop cells were becoming unnecessarily tall.
                // Keep metadata compact while retaining a readable single-column
                // layout on narrow phones.
                childAspectRatio: cols == 1 ? 5.2 : 8.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: [
                  _ReceiptMetaCard(label: 'Facility', value: facilityName),
                  if (courtNumber != null)
                    _ReceiptMetaCard(label: courtLabel ?? 'Field', value: '${courtNumber}'),
                  _ReceiptMetaCard(
                    label: 'Time',
                    value: '${DateFormat('EEE, dd MMM • HH:mm').format(startAt)} - ${DateFormat('HH:mm').format(endAt)}',
                  ),
                  _ReceiptMetaCard(label: 'Booking(s)', value: bookingLabel),
                  _ReceiptMetaCard(label: 'Booking IDs', value: bookingIds.map((e) => '#$e').join(', ')),
                  if (totalHours != null)
                    _ReceiptMetaCard(label: 'Duration', value: '${totalHours!.toStringAsFixed(1)} hour(s)'),
                  _ReceiptMetaCard(
                    label: 'Total',
                    value: '${totalPrice.toStringAsFixed(2)} $currency',
                    highlight: true,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
                    child: const Row(
                      children: [
                        Icon(Icons.pending_actions, size: 34, color: Color(0xFF0F766E)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Check-in QR will be generated after payment confirmation. You can find it in Receipt Center and Booking Details.',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptMetaCard extends StatelessWidget {
  const _ReceiptMetaCard({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontWeight: FontWeight.w800,
      color: highlight ? const Color(0xFF1E40AF) : const Color(0xFF334155),
    );
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
            style: valueStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PaymentSuccessDialog extends StatelessWidget {
  const _PaymentSuccessDialog({
    required this.title,
    required this.message,
    required this.onGoHome,
  });

  final String title;
  final String message;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF15803D),
                size: 42,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onGoHome,
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
