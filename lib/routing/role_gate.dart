import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../supabase_client.dart';
import 'admin_staff_flow.dart';
import 'resident_onboarding_gate.dart';

/// 로그인 후 역할 분기 — **staff_users만** 관리자 플로우 판별.
///
/// | 조건 | 화면 |
/// |------|------|
/// | `staff_users`에 본인 row 있음 | [AdminStaffFlow] (승인 대기 → 대시보드) |
/// | row 없음 | [ResidentOnboardingGate] (이메일 가입 후 5단계 온보딩) |
///
/// 관리자([AdminSignUpScreen])와 입주민([SignUpScreen]) 가입은 별도 화면·RPC이며
/// `user_profiles.role`·`signup_completed`로는 분기하지 않습니다.
class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authUserId = supabase.auth.currentUser?.id;
    debugPrint('[RoleGate] user_id=$authUserId');

    return StreamBuilder<StaffProfile?>(
      stream: StaffRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          debugPrint('[RoleGate] staff_users error: ${snap.error}');
        }

        final staff = snap.data;
        if (staff != null) {
          if (authUserId != null && staff.userId != authUserId) {
            return Scaffold(
              appBar: AppBar(title: const Text('오류')),
              body: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '관리자 계정 정보가 일치하지 않습니다. 다시 로그인해주세요.',
                ),
              ),
            );
          }

          debugPrint('[RoleGate] staff_users → AdminStaffFlow (no resident onboarding)');
          return AdminStaffFlow(initialStaff: staff);
        }

        debugPrint('[RoleGate] no staff_users → ResidentOnboardingGate');
        return const ResidentOnboardingGate();
      },
    );
  }
}
