import 'package:flutter/material.dart';

import '../resident_profile_screen.dart';
import '../screens/booking_screen.dart';
import '../screens/login_screen.dart';
import '../supabase_client.dart';

/// 결제 실패 후 예약 화면으로 복귀할 때 사용
class BookingRoute extends StatelessWidget {
  const BookingRoute({super.key});

  static const _bg = Color(0xFF071826);

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;
    if (session == null) return const LoginScreen();

    return StreamBuilder<ResidentProfile?>(
      stream: ResidentRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
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
  }
}
