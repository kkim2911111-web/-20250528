import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

class AuthService {
  /// 로그아웃 후 회원가입 화면 표시 (AuthGate에서 처리)
  void Function(bool toSignUp)? onSignedOut;

  /// 관리자 가입 RPC 완료 전 — RoleGate(입주민 온보딩) 진입 방지
  bool adminSignUpInProgress = false;

  void beginAdminSignUpFlow() => adminSignUpInProgress = true;

  void endAdminSignUpFlow() => adminSignUpInProgress = false;

  User? get currentUser => supabase.auth.currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _tryGrantWelcomeCoupon();
  }

  /// 웰컴 쿠폰 — RPC 내부 중복 방지, 실패해도 인증 흐름 유지
  Future<void> _tryGrantWelcomeCoupon() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        await supabase.rpc(
          'grant_welcome_coupon',
          params: {'p_user_id': userId},
        );
      }
    } catch (e) {
      // 쿠폰 지급 실패해도 로그인·가입은 정상 처리
    }
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

    if (response.session != null) {
      await _tryGrantWelcomeCoupon();
      return true;
    }

    try {
      await supabase.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
      await _tryGrantWelcomeCoupon();
      return true;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('email not confirmed')) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> signOut({bool toSignUp = false}) async {
    await supabase.auth.signOut();
    onSignedOut?.call(toSignUp);
  }

  Future<void> resetPasswordForEmail({required String email}) async {
    await supabase.auth.resetPasswordForEmail(email.trim());
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
