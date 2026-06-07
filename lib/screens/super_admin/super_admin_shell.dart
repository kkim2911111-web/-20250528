import 'package:flutter/material.dart';

import 'super_admin_dashboard_screen.dart';

/// 최고관리자 루트 — 단지 관리자 대시보드와 동일한 홈 구조
class SuperAdminShell extends StatelessWidget {
  const SuperAdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const SuperAdminDashboardScreen();
  }
}
