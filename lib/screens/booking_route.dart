import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../resident_profile_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_pending_screen.dart';
import '../screens/booking_screen.dart';
import '../screens/login_screen.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';

/// 결제 실패 후 예약 화면 복귀 — 관리자 계정은 지점 관리로 분기
class BookingRoute extends StatelessWidget {
  const BookingRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;
    if (session == null) return const LoginScreen();

    return StreamBuilder<StaffProfile?>(
      stream: StaffRepository().watchMyProfile(),
      builder: (context, staffSnap) {
        final staff = staffSnap.data;
        if (staff != null) {
          if (!staff.isApproved) {
            return AdminPendingScreen(profile: staff);
          }
          return AdminDashboardScreen(profile: staff);
        }

        if (staffSnap.connectionState == ConnectionState.waiting &&
            !staffSnap.hasData) {
          return const Scaffold(
            backgroundColor: DanjiColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return StreamBuilder<ResidentProfile?>(
          stream: ResidentRepository().watchMyProfile(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Scaffold(
                backgroundColor: DanjiColors.background,
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final profile = snap.data;
            if (profile == null || profile.approved != true) {
              return const ResidentProfileScreen();
            }

            return const BookingScreen();
          },
        );
      },
    );
  }
}
