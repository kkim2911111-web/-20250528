import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/supabase_bootstrap.dart';

bool get isSupabaseInitialized => isSupabaseBootstrapReady;

SupabaseClient get supabase {
  if (!isSupabaseBootstrapReady) {
    throw StateError(
      '서버(Supabase)에 아직 연결되지 않았습니다.\n'
      '네트워크 연결을 확인한 뒤 앱을 다시 실행해주세요.',
    );
  }
  return Supabase.instance.client;
}

SupabaseClient? get supabaseOrNull =>
    isSupabaseBootstrapReady ? Supabase.instance.client : null;
