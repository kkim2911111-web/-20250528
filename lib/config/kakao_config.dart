import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 카카오 개발자 앱 — JavaScript Key (주소 검색 WebView)
class KakaoConfig {
  static const _fromDefine = String.fromEnvironment('KAKAO_JAVASCRIPT_KEY');

  static String get javascriptKey {
    if (_fromDefine.isNotEmpty) return _fromDefine;
    final fromEnv = dotenv.env['KAKAO_JAVASCRIPT_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return '';
  }

  static bool get isConfigured => javascriptKey.isNotEmpty;

  /// WebView baseUrl — 카카오 개발자 콘솔 Web 플랫폼 사이트 도메인과 일치해야 함
  static const webViewBaseUrl = 'https://danjicar.vercel.app';

  static String get keySource {
    if (_fromDefine.isNotEmpty) return 'dart-define';
    final fromEnv = dotenv.env['KAKAO_JAVASCRIPT_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return '.env';
    return 'unset';
  }

  static String get maskedKey {
    final key = javascriptKey;
    if (key.length <= 12) return '***';
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }

  static void logLoadedKey() {
    debugPrint(
      '[KakaoConfig] KAKAO_JAVASCRIPT_KEY from $keySource: '
      '${isConfigured ? maskedKey : '(not set)'}',
    );
  }
}
