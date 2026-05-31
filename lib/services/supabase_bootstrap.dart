import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/network_retry.dart';

bool _supabaseReady = false;

/// Supabase.instance 접근 전 안전하게 확인 (미초기화 시 getter assert 방지)
bool get isSupabaseBootstrapReady => _supabaseReady;

/// 앱 시작 시 Supabase 초기화 (네트워크 준비 대기 + 최대 3회 재시도)
Future<void> initializeSupabaseWithRetry() async {
  if (_supabaseReady) return;

  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'SUPABASE_URL 또는 SUPABASE_ANON_KEY가 설정되지 않았습니다.\n'
      'assets/.env 또는 --dart-define를 확인해주세요.',
    );
  }

  await withNetworkRetry(
    () => Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    ),
  );
  _supabaseReady = true;
}
