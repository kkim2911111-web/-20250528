import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase URL / anon key — .env → dart-define → 기본값 순
class SupabaseConfig {
  static const defaultUrl = 'https://knxkmngonkzchwelpdjn.supabase.co';
  static const defaultAnonKey =
      'sb_publishable_Mg_xNFRdV1QoH_-m0IsKGQ_fZJbfl6t';

  static Future<void> loadEnv() async {
    try {
      await dotenv.load(fileName: '.env', isOptional: true);
    } catch (_) {
      // .env 없거나 웹 번들 미포함 — dart-define / 기본값 사용
    }
  }

  static String get url {
    final fromEnv = dotenv.env['SUPABASE_URL']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    const fromDefine = String.fromEnvironment('SUPABASE_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    return defaultUrl;
  }

  static String get anonKey {
    final fromEnv = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    const fromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    return defaultAnonKey;
  }

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
