import 'package:flutter/material.dart';

import '../services/payment_service.dart';

/// 토스 결제 실패/취소 리다이렉트 → 주문 취소 후 예약 화면 복귀
class PaymentFailScreen extends StatefulWidget {
  final Map<String, String> queryParams;

  const PaymentFailScreen({super.key, required this.queryParams});

  @override
  State<PaymentFailScreen> createState() => _PaymentFailScreenState();
}

class _PaymentFailScreenState extends State<PaymentFailScreen> {
  static const _bg = Color(0xFF071826);
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

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
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator(color: _textPrimary)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cancel_outlined,
                        color: Colors.orangeAccent, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      '결제 실패',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '예약이 취소되었습니다.',
                      style: TextStyle(color: _textSecondary),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _goBooking,
                      child: const Text('예약 화면으로 돌아가기'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
