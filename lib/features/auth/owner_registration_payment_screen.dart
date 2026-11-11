import 'package:flutter/material.dart';

import '../booking/payment_method_selector.dart';

class OwnerRegistrationPaymentScreen extends StatefulWidget {
  const OwnerRegistrationPaymentScreen({super.key});

  @override
  State<OwnerRegistrationPaymentScreen> createState() =>
      _OwnerRegistrationPaymentScreenState();
}

class _OwnerRegistrationPaymentScreenState
    extends State<OwnerRegistrationPaymentScreen> {
  int _selectedMethod = 0;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Registration Checkout'),
        backgroundColor: const Color(0xFFF8FAFC),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FAFB), Color(0xFFEDEFF2)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 22,
                  16,
                  compact ? 14 : 22,
                  24,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.storefront_outlined, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'VENUE OWNER PLAN',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Activate your owner account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'One-time simulated registration payment. Your owner account is created after you confirm.',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Divider(color: Color(0xFF64748B)),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$20.00',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 8),
                            Padding(
                              padding: EdgeInsets.only(bottom: 5),
                              child: Text(
                                'USD • one-time',
                                style: TextStyle(color: Color(0xFFCBD5E1)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(compact ? 12 : 16),
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
                      methods: standardPaymentMethods,
                      selectedIndex: _selectedMethod,
                      onSelected: (index) =>
                          setState(() => _selectedMethod = index),
                      compact: compact,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF92400E)),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Prototype mode: this payment is simulated. No real money is charged. Cancel to leave registration without creating an owner account.',
                            style: TextStyle(
                              color: Color(0xFF78350F),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        final method = standardPaymentMethods[_selectedMethod];
                        Navigator.of(context).pop({
                          'provider': method.provider,
                          'channel': method.channel,
                        });
                      },
                      icon: const Icon(Icons.lock_outline),
                      label: const Text(
                        'Confirm Simulated Payment • \$20.00',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel registration'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
