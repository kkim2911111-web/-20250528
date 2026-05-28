import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

class AuthService {
  User? get currentUser => supabase.auth.currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// 회원가입 후 세션이 없으면 즉시 로그인 시도 (이메일 인증 OFF 설정용)
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();

    final response = await supabase.auth.signUp(
      email: trimmedEmail,
      password: password,
    );

    if (response.session != null) return;

    try {
      await supabase.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('email not confirmed')) {
        throw const AuthException(
          'Supabase에서 이메일 인증이 켜져 있습니다. '
          'Dashboard > Authentication > Email > Confirm email 을 OFF 로 바꿔주세요.',
        );
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}

String friendlyAuthError(Object e) {
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (msg.contains('email not confirmed')) {
      return '이메일 인증이 필요합니다. Supabase에서 Confirm email을 OFF로 설정하세요.';
    }
    if (msg.contains('user already registered')) {
      return '이미 가입된 이메일입니다.';
    }
    if (msg.contains('password')) {
      return '비밀번호 형식을 확인해주세요. (6자 이상 권장)';
    }
    return e.message;
  }
  return e.toString();
}
