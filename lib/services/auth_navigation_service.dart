import 'package:flutter/material.dart';

import '../routing/app_routes.dart';

/// 로그아웃·세션 만료 시 루트 네비게이터를 인증 진입점으로 되돌림.
///
/// 결제 완료 등에서 [MainShell]이 [AuthGate] 위로 올라간 경우,
/// [AuthGate]의 콜백만으로는 로그인/회원가입 화면 전환이 되지 않습니다.
class AuthNavigationService {
  AuthNavigationService._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// [AuthGate]가 위젯 트리에 마운트되어 있으면 true
  static bool authGateActive = false;

  static void bindNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static void resetToAuthEntry() {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntry()),
      (_) => false,
    );
  }
}
