import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../routing/app_routes.dart';
import '../config/payment_config.dart';
import '../models/payment_confirm_result.dart';
import '../services/payment_service.dart';
import '../services/rental_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../screens/rental_start_screen.dart';
import '../screens/main_shell.dart';
import 'my_reservations_screen.dart';

/// 토스 결제 성공 리다이렉트 → Edge Function 승인 → 예약 완료
class PaymentSuccessScreen extends StatefulWidget {
  final Map<String, String> queryParams;

  const PaymentSuccessScreen({super.key, required this.queryParams});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  /// 세션 단위 — initState 이중 실행·재마운트 방지
  static final _handledOrderIds = <String>{};
  static final _inflightOrderIds = <String>{};
  static final _navigatedOrderIds = <String>{};
  static final _handledResults = <String, PaymentConfirmResult>{};
  static final _bootstrappedOrderIds = <String>{};

  final _paymentService = PaymentService();
  final _won = NumberFormat('#,###');

  bool _loading = true;
  bool _isConfirming = false;
  String? _error;
  PaymentConfirmResult? _result;
  int? _amount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runConfirmOnce());
  }

  Map<String, String> get _params {
    if (widget.queryParams.isNotEmpty) {
      return widget.queryParams;
    }
    // Web(테스트): URL 쿼리 파라미터
    if (kIsWeb) {
      final merged = paymentQueryParams();
      if (merged.isNotEmpty) return merged;
      return Uri.base.queryParameters;
    }
    return const {};
  }

  int? _parseAmount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw) ?? double.tryParse(raw)?.round();
  }

  /// initState 1회만 _confirm 실행 (React StrictMode 이중 실행 대응)
  Future<void> _runConfirmOnce() async {
    await _waitForSupabaseReady();

    final orderId = _params['orderId'] ?? _params['order_id'];
    if (orderId != null && _bootstrappedOrderIds.contains(orderId)) {
      debugPrint('[payment/success] skip duplicate bootstrap for $orderId');
      return;
    }
    if (orderId != null) {
      _bootstrappedOrderIds.add(orderId);
    }
    await _confirm();
  }

  Future<void> _confirm({bool manualRetry = false}) async {
    if (_isConfirming && !manualRetry) {
      debugPrint('[payment/success] skip — confirm already in progress');
      return;
    }

    final p = _params;
    final paymentKey = p['paymentKey'] ?? p['payment_key'];
    final orderId = p['orderId'] ?? p['order_id'];
    final amountStr = p['amount'];

    _logPaymentParams(
      paymentKey: paymentKey,
      orderId: orderId,
      amount: amountStr,
    );

    if (manualRetry && orderId != null) {
      _handledOrderIds.remove(orderId);
      _handledResults.remove(orderId);
      _navigatedOrderIds.remove(orderId);
    }

    if (orderId != null &&
        !manualRetry &&
        (_inflightOrderIds.contains(orderId) ||
            _handledOrderIds.contains(orderId))) {
      debugPrint(
        '[payment/success] skip duplicate _confirm for orderId=$orderId',
      );
      if (_handledOrderIds.contains(orderId)) {
        await _finishFromCache(orderId);
      }
      return;
    }

    if (paymentKey == null || orderId == null || amountStr == null) {
      setState(() {
        _loading = false;
        _error = kIsWeb
            ? '결제 정보가 URL에 없습니다.\n'
                '토스 결제 완료 후 자동으로 이 화면으로 와야 합니다.\n'
                '현재 URL: ${Uri.base}'
            : '결제 승인 정보(paymentKey, orderId, amount)를 받지 못했습니다.\n'
                '결제를 다시 시도해주세요.';
      });
      return;
    }

    final amount = _parseAmount(amountStr);
    if (amount == null) {
      setState(() {
        _loading = false;
        _error = '결제 금액 형식이 올바르지 않습니다: $amountStr';
      });
      return;
    }

    _isConfirming = true;
    _inflightOrderIds.add(orderId);
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // 1) 승인 API 호출 전 — DB에 이미 처리된 주문인지 먼저 확인
      final preResolved = await _paymentService.tryResolveExistingPayment(
        orderId: orderId,
        paymentKey: paymentKey,
      );
      if (preResolved != null && preResolved.reservationId.isNotEmpty) {
        debugPrint(
          '[payment/success] already processed in DB — skip approval API',
        );
        await _onConfirmSuccess(
          result: preResolved,
          orderId: orderId,
          amountStr: amountStr,
        );
        return;
      }

      await _waitForAuthSession();

      if (supabase.auth.currentUser == null) {
        setState(() {
          _loading = false;
          _error =
              '로그인 세션이 만료되었습니다.\n'
              '다시 로그인한 뒤 아래 [예약 저장 재시도]를 눌러주세요.';
        });
        return;
      }

      // 2) 승인 API (PaymentService 내부에서도 orderId별 in-flight dedupe)
      final result = await _paymentService.onPaymentSuccess(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
      debugPrint(
        '[payment/success] onPaymentSuccess result: '
        'reservationId=${result.reservationId}, orderId=${result.orderId}',
      );

      if (result.reservationId.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              '결제는 완료되었으나 예약이 저장되지 않았습니다.\n'
              '아래 [예약 저장 재시도]를 눌러주세요.';
        });
        return;
      }

      await _onConfirmSuccess(
        result: result,
        orderId: orderId,
        amountStr: amountStr,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyPaymentError(e);
        });
      }
    } finally {
      _isConfirming = false;
      _inflightOrderIds.remove(orderId);
    }
  }

  Future<void> _onConfirmSuccess({
    required PaymentConfirmResult result,
    required String orderId,
    required String amountStr,
  }) async {
    _handledResults[orderId] = result;
    _handledOrderIds.add(orderId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
      _amount = int.tryParse(amountStr);
    });
    await _goToMyReservations(
      reservationId: result.reservationId,
      orderId: orderId,
    );
  }

  Future<void> _finishFromCache(String orderId) async {
    final cached = _handledResults[orderId];
    if (cached == null || cached.reservationId.isEmpty) return;
    if (mounted) {
      setState(() {
        _loading = false;
        _result = cached;
      });
    }
    await _goToMyReservations(
      reservationId: cached.reservationId,
      orderId: orderId,
    );
  }

  void _logPaymentParams({
    required String? paymentKey,
    required String? orderId,
    required String? amount,
  }) {
    debugPrint('[payment/success] full URL: ${Uri.base}');
    debugPrint('[payment/success] query params: $_params');
    debugPrint(
      '[payment/success] paymentKey=${paymentKey ?? '(null)'}, '
      'orderId=${orderId ?? '(null)'}, '
      'amount=${amount ?? '(null)'}',
    );
  }

  Future<void> _goToMyReservations({
    String? reservationId,
    String? orderId,
  }) async {
    final navKey = orderId ?? reservationId ?? '';
    if (navKey.isNotEmpty && _navigatedOrderIds.contains(navKey)) {
      debugPrint(
        '[payment/success] skip duplicate navigation to my reservations',
      );
      return;
    }
    if (navKey.isNotEmpty) {
      _navigatedOrderIds.add(navKey);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('결제가 완료되었습니다. 내 예약으로 이동합니다.')),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
    if (!mounted) return;

    RentalService.signalListRefresh();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const MyReservationsScreen(forceRefreshOnOpen: true),
      ),
    );
  }

  Future<void> _waitForSupabaseReady() async {
    if (Supabase.instance.isInitialized) return;

    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (Supabase.instance.isInitialized) return;
    }
    throw StateError('Supabase 초기화 대기 시간 초과');
  }

  Future<void> _waitForAuthSession() async {
    if (supabase.auth.currentSession != null) return;

    final completer = Completer<void>();
    late final StreamSubscription<AuthState> sub;

    sub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null && !completer.isCompleted) {
        completer.complete();
      }
    });

    unawaited(
      Future<void>.delayed(const Duration(seconds: 12), () {
        if (!completer.isCompleted) completer.complete();
      }),
    );

    await completer.future;
    await sub.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      '결제 확인 중...',
                      style: TextStyle(color: DanjiColors.textSecondary),
                    ),
                  ],
                )
              : _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: DanjiColors.accentRed, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: DanjiColors.accentRed),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _isConfirming
                              ? null
                              : () => _confirm(manualRetry: true),
                          child: const Text('예약 저장 재시도'),
                        ),
                        const SizedBox(height: 8),
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
                            color: DanjiColors.buttonBlue, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          '결제가 완료되었습니다.',
                          style: TextStyle(
                            color: DanjiColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '예약이 정상적으로 확정되었습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: DanjiColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        if (_amount != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '결제 금액: ₩${_won.format(_amount)}',
                            style: const TextStyle(
                              color: DanjiColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_result != null) ...[
                          if (_result!.vehicleName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '차량: ${_result!.vehicleName}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '예약 ID: ${_result!.reservationId}',
                            style: const TextStyle(
                              color: DanjiColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '주문 ID: ${_result!.orderId}',
                            style: const TextStyle(
                              color: DanjiColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (PaymentConfig.isTestKey) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '(테스트 모드 — 실제 청구되지 않음)',
                            style: TextStyle(
                              color: DanjiColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (_result != null &&
                            _result!.reservationId.isNotEmpty)
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => RentalStartScreen(
                                    reservationId: _result!.reservationId,
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: DanjiColors.buttonBlue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('대여하기'),
                          ),
                        if (_result != null &&
                            _result!.reservationId.isNotEmpty)
                          const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_result != null &&
                                _result!.reservationId.isNotEmpty)
                              OutlinedButton(
                                onPressed: _isConfirming
                                    ? null
                                    : () async {
                                        await _goToMyReservations(
                                          reservationId: _result!.reservationId,
                                          orderId: _result!.orderId,
                                        );
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: DanjiColors.buttonBlue,
                                  side: const BorderSide(
                                    color: DanjiColors.buttonBlue,
                                  ),
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
