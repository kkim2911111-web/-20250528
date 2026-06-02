import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_pending_screen.dart';

/// staff_users 기준 관리자 화면 — 승인 시 대시보드로 자동 전환
class AdminStaffFlow extends StatelessWidget {
  final StaffProfile initialStaff;

  const AdminStaffFlow({super.key, required this.initialStaff});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StaffProfile?>(
      stream: StaffRepository().watchMyProfile(),
      initialData: initialStaff,
      builder: (context, snap) {
        final staff = snap.data ?? initialStaff;

        if (staff.isApproved) {
          return AdminDashboardScreen(profile: staff);
        }

        return AdminPendingScreen(
          profile: staff,
          displayName: staff.displayName,
          complexName: staff.complexName,
        );
      },
    );
  }
}
