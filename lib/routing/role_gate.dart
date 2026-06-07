import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../screens/super_admin/super_admin_shell.dart';
import '../services/super_admin_service.dart';
import '../supabase_client.dart';
import 'admin_staff_flow.dart';
import 'resident_onboarding_gate.dart';

/// 로그인 후 역할 분기
///
/// | 조건 | 화면 |
/// |------|------|
/// | `user_profiles.is_super_admin` | [SuperAdminShell] |
/// | `staff_users`에 본인 row 있음 | [AdminStaffFlow] |
/// | row 없음 | [ResidentOnboardingGate] |
///
/// 관리자([AdminSignUpScreen])와 입주민([SignUpScreen]) 가입은 별도 화면·RPC이며
/// `user_profiles.role`·`signup_completed`로는 분기하지 않습니다.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  final _superAdmin = SuperAdminService();
  late final Future<bool> _superAdminFuture = _superAdmin.isSuperAdmin();

  @override
  Widget build(BuildContext context) {
    final authUserId = supabase.auth.currentUser?.id;
    debugPrint('[RoleGate] user_id=$authUserId');

    return FutureBuilder<bool>(
      future: _superAdminFuture,
      builder: (context, superSnap) {
        if (superSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (superSnap.data == true) {
          debugPrint('[RoleGate] is_super_admin → SuperAdminShell');
          return const SuperAdminShell();
        }
        return _staffOrResidentGate(authUserId);
      },
    );
  }

  Widget _staffOrResidentGate(String? authUserId) {
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
