import 'package:flutter/material.dart';

import '../../models/admin_messages.dart';
import '../../models/staff_profile.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/danji_app_bar.dart';

/// 지점 관리자 승인 대기 — 입주민 화면으로 넘어가지 않음
class AdminPendingScreen extends StatelessWidget {
  final StaffProfile profile;

  const AdminPendingScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '관리자',
        showHome: false,
        showBack: false,
        extraActions: [
          TextButton(
            onPressed: () => AuthService().signOut(),
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: DanjiColors.skyLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 36,
                    color: DanjiColors.buttonBlue,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  AdminMessages.pendingApproval,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DanjiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${profile.displayName}님 · ${profile.complexName ?? '지점'}\n'
                  '승인 완료 후 지점 관리 페이지가 열립니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
