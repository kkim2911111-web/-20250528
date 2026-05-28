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

  /// 회원가입. true면 로그인 완료, false면 이메일 확인 후 인증 필요.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();

    final response = await supabase.auth.signUp(
      email: trimmedEmail,
      password: password,
    );

    if (response.session != null) return true;

    try {
      await supabase.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
      return true;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('email not confirmed')) {
        return false;
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
      return '이메일 확인 후 로그인해주세요.';
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

const emailSignUpConfirmationMessage =
    '이메일가입은 이메일 확인후 인증을 진행해주세요';
