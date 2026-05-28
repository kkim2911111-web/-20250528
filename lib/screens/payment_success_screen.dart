import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/payment_config.dart';
import '../models/payment_confirm_result.dart';
import '../services/payment_service.dart';
import 'my_reservations_screen.dart';

/// 토스 결제 성공 리다이렉트 → Edge Function 승인 → 예약 완료
class PaymentSuccessScreen extends StatefulWidget {
  final Map<String, String> queryParams;

  const PaymentSuccessScreen({super.key, required this.queryParams});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  static const _bg = Color(0xFF071826);
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

  final _paymentService = PaymentService();
  final _won = NumberFormat('#,###');

  bool _loading = true;
  String? _error;
  PaymentConfirmResult? _result;
  int? _amount;

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    final p = widget.queryParams;
    final paymentKey = p['paymentKey'];
    final orderId = p['orderId'];
    final amountStr = p['amount'];

    if (paymentKey == null || orderId == null || amountStr == null) {
      setState(() {
        _loading = false;
        _error = '결제 정보가 올바르지 않습니다.';
      });
      return;
    }

    try {
      final result = await _paymentService.onPaymentSuccess(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: int.parse(amountStr),
      );
      setState(() {
        _loading = false;
        _result = result;
        _amount = int.tryParse(amountStr);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('결제가 완료되었습니다.')),
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _textPrimary),
                    SizedBox(height: 16),
                    Text('결제 확인 중...', style: TextStyle(color: _textSecondary)),
                  ],
                )
              : _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.of(context)
                              .pushReplacementNamed('/booking'),
                          child: const Text('예약 화면으로'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF7EE2A8), size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          '결제가 완료되었습니다.',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '예약이 정상적으로 확정되었습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textSecondary, height: 1.4),
                        ),
                        if (_amount != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '결제 금액: ₩${_won.format(_amount)}',
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_result != null) ...[
                          if (_result!.vehicleName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '차량: ${_result!.vehicleName}',
                              style: const TextStyle(color: _textSecondary),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '예약 ID: ${_result!.reservationId}',
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '주문 ID: ${_result!.orderId}',
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (PaymentConfig.isTestKey) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '(테스트 모드 — 실제 청구되지 않음)',
                            style: TextStyle(color: _textSecondary, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_result != null &&
                                _result!.reservationId.isNotEmpty)
                              OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MyReservationsScreen(),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _textPrimary,
                                  side: const BorderSide(color: _textSecondary),
                                ),
                                child: const Text('내 예약 보기'),
                              ),
                            if (_result != null &&
                                _result!.reservationId.isNotEmpty)
                              const SizedBox(width: 12),
                            FilledButton(
                              onPressed: () => Navigator.of(context)
                                  .pushReplacementNamed('/home'),
                              child: const Text('홈으로'),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
