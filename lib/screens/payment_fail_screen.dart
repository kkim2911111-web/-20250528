import 'package:flutter/material.dart';

import '../services/payment_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';

/// 토스 결제 실패/취소 리다이렉트 → 주문 취소 후 예약 화면 복귀
class PaymentFailScreen extends StatefulWidget {
  final Map<String, String> queryParams;

  const PaymentFailScreen({super.key, required this.queryParams});

  @override
  State<PaymentFailScreen> createState() => _PaymentFailScreenState();
}

class _PaymentFailScreenState extends State<PaymentFailScreen> {
  final _paymentService = PaymentService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cancel();
  }

  Future<void> _cancel() async {
    final p = widget.queryParams;
    final orderId = p['orderId'];
    if (orderId != null) {
      await _paymentService.cancelPayment(
        orderId: orderId,
        code: p['code'],
        message: p['message'],
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goBooking() {
    Navigator.of(context).pushReplacementNamed('/booking');
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.queryParams['message'] ?? '결제가 취소되었습니다.';

    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cancel_outlined,
                        color: DanjiColors.accentRed, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      '결제 실패',
                      style: TextStyle(
                        color: DanjiColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '예약이 취소되었습니다.',
                      style: TextStyle(color: DanjiColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _goBooking,
                      style: DanjiTheme.primaryButton,
                      child: const Text('예약 화면으로 돌아가기'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
