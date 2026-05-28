/// 토스페이먼츠 클라이언트 키 (--dart-define 또는 기본 테스트 키)
class PaymentConfig {
  static const tossClientKey = String.fromEnvironment(
    'TOSS_CLIENT_KEY',
    defaultValue: 'test_ck_6BYq7GWPVv4NoQ49k05n8NE5vbo1',
  );

  static bool get isConfigured => tossClientKey.isNotEmpty;

  static bool get isTestKey => tossClientKey.startsWith('test_ck_');
}

enum TossPaymentMethod {
  card('CARD', '카드'),
  transfer('TRANSFER', '계좌이체'),
  kakaoPay('CARD', '카카오페이');

  final String tossMethod;
  final String label;
  const TossPaymentMethod(this.tossMethod, this.label);

  bool get isKakaoPay => this == TossPaymentMethod.kakaoPay;
}
