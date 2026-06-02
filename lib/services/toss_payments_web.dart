// Web 전용 — VM analyze 시 dart:js_util URI 경고 무시
// ignore_for_file: uri_does_not_exist

import 'dart:js_util' as js_util;

import '../config/payment_config.dart';

class TossPaymentsLauncher {
  Object? get _danjiToss => js_util.getProperty(js_util.globalThis, 'DanjiToss');

  bool get isReady {
    if (js_util.getProperty(js_util.globalThis, 'TossPayments') == null) {
      return false;
    }
    return _danjiToss != null;
  }

  Future<void> requestPayment({
    required String orderId,
    required String orderName,
    required int amount,
    required String customerKey,
    required TossPaymentMethod method,
    String? customerEmail,
    String? customerName,
  }) async {
    if (!PaymentConfig.isConfigured) {
      throw StateError(
        'TOSS_CLIENT_KEY가 설정되지 않았습니다.\n'
        'flutter run -d chrome --dart-define=TOSS_CLIENT_KEY=test_ck_...',
      );
    }

    final danjiToss = _danjiToss;
    if (danjiToss == null) {
      throw StateError('Toss 브릿지(DanjiToss)가 로드되지 않았습니다.');
    }

    final options = <String, dynamic>{
      'clientKey': PaymentConfig.tossClientKey,
      'method': method.tossMethod,
      'amount': amount,
      'orderId': orderId,
      'orderName': orderName,
      'customerKey': customerKey,
      'successUrl': '$origin/payment/success',
      'failUrl': '$origin/payment/fail',
      if (customerEmail != null) 'customerEmail': customerEmail,
      if (customerName != null) 'customerName': customerName,
      if (method.isKakaoPay) 'easyPay': 'KAKAOPAY',
    };

    final promise = js_util.callMethod(
      danjiToss,
      'requestPayment',
      [js_util.jsify(options)],
    );
    await js_util.promiseToFuture(promise);
  }

  /// 빌링키 발급 (실결제 없음) — 성공 시 브라우저가 successUrl로 이동
  Future<void> requestBillingAuth({
    required String customerKey,
    String? customerEmail,
    String? customerName,
  }) async {
    if (!PaymentConfig.isConfigured) {
      throw StateError(
        'TOSS_CLIENT_KEY가 설정되지 않았습니다.\n'
        'flutter run -d chrome --dart-define=TOSS_CLIENT_KEY=test_ck_...',
      );
    }

    final danjiToss = _danjiToss;
    if (danjiToss == null) {
      throw StateError('Toss 브릿지(DanjiToss)가 로드되지 않았습니다.');
    }

    final options = <String, dynamic>{
      'clientKey': PaymentConfig.tossClientKey,
      'customerKey': customerKey,
      'successUrl': '$origin/payment/billing-success',
      'failUrl': '$origin/payment/billing-fail',
      if (customerEmail != null) 'customerEmail': customerEmail,
      if (customerName != null) 'customerName': customerName,
    };

    final promise = js_util.callMethod(
      danjiToss,
      'requestBillingAuth',
      [js_util.jsify(options)],
    );
    await js_util.promiseToFuture(promise);
  }

  String get origin {
    final danjiToss = _danjiToss;
    if (danjiToss == null) return '';
    return js_util.callMethod(danjiToss, 'getOrigin', []) as String? ?? '';
  }
}
