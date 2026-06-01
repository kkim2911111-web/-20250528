import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../resident_profile_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_pending_screen.dart';
import '../screens/booking_screen.dart';
import '../screens/login_screen.dart';
import '../services/my_page_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../utils/booking_eligibility.dart';

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

            return _BookingEligibilityGate(
              child: const BookingScreen(),
            );
          },
        );
      },
    );
  }
}

class _BookingEligibilityGate extends StatefulWidget {
  final Widget child;

  const _BookingEligibilityGate({required this.child});

  @override
  State<_BookingEligibilityGate> createState() => _BookingEligibilityGateState();
}

class _BookingEligibilityGateState extends State<_BookingEligibilityGate> {
  final _myPage = MyPageService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _myPage.fetchProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: DanjiColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('차량 예약')),
            body: Center(child: Text('프로필 확인 실패: ${snap.error}')),
          );
        }

        final profile = snap.data!;
        final block = BookingEligibility.blockReason(profile);
        if (block != null) {
          return Scaffold(
            backgroundColor: DanjiColors.background,
            appBar: AppBar(
              title: const Text('차량 예약'),
              backgroundColor: DanjiColors.background,
            ),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 48,
                    color: DanjiColors.accentRed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    block,
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('돌아가기'),
                  ),
                ],
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
