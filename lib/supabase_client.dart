import 'package:supabase_flutter/supabase_flutter.dart';

bool get isSupabaseInitialized => Supabase.instance.isInitialized;

SupabaseClient get supabase {
  if (!Supabase.instance.isInitialized) {
    throw StateError(
      'Supabase가 아직 초기화되지 않았습니다. '
      '앱을 새로고침하거나 .env의 SUPABASE_URL·SUPABASE_ANON_KEY를 확인해주세요.',
    );
  }
  return Supabase.instance.client;
}

SupabaseClient? get supabaseOrNull =>
    Supabase.instance.isInitialized ? Supabase.instance.client : null;
