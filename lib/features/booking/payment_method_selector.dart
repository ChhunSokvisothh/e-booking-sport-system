import 'package:flutter/material.dart';

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.provider,
    required this.channel,
    required this.icon,
  });

  final String provider;
  final String channel;
  final IconData icon;
}

const List<PaymentMethodOption> standardPaymentMethods = [
  PaymentMethodOption(
    channel: 'local_bank',
    provider: 'Bakong QR',
    icon: Icons.qr_code_2,
  ),
  PaymentMethodOption(
    channel: 'local_bank',
    provider: 'ABA Bank',
    icon: Icons.account_balance,
  ),
  PaymentMethodOption(
    channel: 'card',
    provider: 'Visa',
    icon: Icons.credit_card,
  ),
  PaymentMethodOption(
    channel: 'card',
    provider: 'Mastercard',
    icon: Icons.credit_card,
  ),
  PaymentMethodOption(
    channel: 'international_bank',
    provider: 'PayPal',
    icon: Icons.public,
  ),
];

class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({
    super.key,
    required this.methods,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
  });

  final List<PaymentMethodOption> methods;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tiny = compact || MediaQuery.sizeOf(context).width < 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: tiny ? 15.5 : 17,
          ),
        ),
        SizedBox(height: tiny ? 8 : 10),
        ...List.generate(methods.length, (index) {
          final method = methods[index];
          final selected = selectedIndex == index;
          return Padding(
            padding: EdgeInsets.only(bottom: tiny ? 6 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(index),
              child: Ink(
                padding: EdgeInsets.symmetric(
                  horizontal: tiny ? 8 : 10,
                  vertical: tiny ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFFDBEAFE), Color(0xFFE0F2FE)],
                        )
                      : const LinearGradient(
                          colors: [Colors.white, Colors.white],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      method.icon,
                      color: const Color(0xFF334155),
                      size: tiny ? 18 : 22,
                    ),
                    SizedBox(width: tiny ? 8 : 10),
                    Expanded(
                      child: Text(
                        method.provider,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: tiny ? 13 : 15,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF94A3B8),
                      size: tiny ? 20 : 28,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
