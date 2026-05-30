import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 토스페이먼츠 클라이언트 키 — dart-define → .env → 기본 테스트 키
class PaymentConfig {
  static const _defaultKey = 'test_ck_6BYq7GWPVv4NoQ49k05n8NE5vbo1';
  static const _fromDefine = String.fromEnvironment('TOSS_CLIENT_KEY');

  static String get tossClientKey {
    if (_fromDefine.isNotEmpty) return _fromDefine;
    final fromEnv = dotenv.env['TOSS_CLIENT_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _defaultKey;
  }

  static bool get isConfigured => tossClientKey.isNotEmpty;

  static bool get isTestKey => tossClientKey.startsWith('test_ck_');

  /// 디버그용 — 키 출처
  static String get keySource {
    if (_fromDefine.isNotEmpty) return 'dart-define';
    final fromEnv = dotenv.env['TOSS_CLIENT_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return '.env';
    return 'default';
  }

  static String get maskedKey {
    final key = tossClientKey;
    if (key.length <= 12) return '***';
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }

  static void logLoadedKey() {
    debugPrint(
      '[PaymentConfig] TOSS_CLIENT_KEY loaded from $keySource: $maskedKey',
    );
  }
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
