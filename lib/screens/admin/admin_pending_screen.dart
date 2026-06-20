import 'package:flutter/material.dart';

import '../../models/admin_messages.dart';
import '../../models/staff_profile.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/logout_confirm_dialog.dart';

/// 지점 관리자 승인 대기 — 입주민 온보딩/인증 화면으로 넘어가지 않음
class AdminPendingScreen extends StatelessWidget {
  final StaffProfile? profile;
  final String? displayName;
  final String? complexName;

  const AdminPendingScreen({
    super.key,
    this.profile,
    this.displayName,
    this.complexName,
  });

  String get _displayName =>
      profile?.displayName ?? displayName?.trim() ?? '관리자';

  String get _complexName =>
      profile?.complexName ?? complexName?.trim() ?? '지점';

  String get _contactLine {
    final parts = <String>[
      if ((profile?.companyName?.trim().isNotEmpty ?? false))
        profile!.companyName!.trim(),
      if ((profile?.phone?.trim().isNotEmpty ?? false)) profile!.phone!.trim(),
    ];
    if (parts.isEmpty) return '';
    return '\n${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: DanjiAppBar(
        title: '관리자',
        showHome: false,
        showBack: false,
        extraActions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showLogoutConfirmDialog(context);
              if (!confirmed || !context.mounted) return;
              await AuthService.instance.signOut();
            },
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
                  '$_displayName님 · $_complexName$_contactLine\n'
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
