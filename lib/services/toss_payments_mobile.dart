import '../config/payment_config.dart';

/// Android/iOS — 결제는 [PaymentService.openTossPayment] WebView 경로 사용
class TossPaymentsLauncher {
  bool get isReady => PaymentConfig.isConfigured;

  Future<void> requestPayment({
    required String orderId,
    required String orderName,
    required int amount,
    required String customerKey,
    required TossPaymentMethod method,
    String? customerEmail,
    String? customerName,
  }) {
    throw UnsupportedError(
      '모바일 결제는 PaymentService.openTossPayment(context: ...)을 사용하세요.',
    );
  }

  Future<void> requestBillingAuth({
    required String customerKey,
    String? customerEmail,
    String? customerName,
  }) {
    throw UnsupportedError(
      '모바일 빌링키 발급은 TossBillingWebViewScreen을 사용하세요.',
    );
  }

  String get origin => PaymentConfig.mobilePaymentOrigin;
}
