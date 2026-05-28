import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../supabase_client.dart';
import '../resident_profile_screen.dart';
import '../reservations_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _bg = Color(0xFF071826);
  static const _card = Color(0xFF0B2235);
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '입주민';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('단지카'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: () async {
              await AuthService().signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(
              '안녕하세요, $email 님',
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '우리 단지의 두 번째 차, 단지카에 오신 것을 환영합니다.',
              style: TextStyle(color: _textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            _HomeCard(
              icon: Icons.verified_user_outlined,
              title: '입주민 인증',
              subtitle: '초대코드와 동/호수를 등록하세요.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResidentProfileScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _HomeCard(
              icon: Icons.directions_car_outlined,
              title: '차량 예약',
              subtitle: '단지 공용차를 예약합니다.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ReservationsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomeScreen._card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: HomeScreen._textPrimary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: HomeScreen._textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: HomeScreen._textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: HomeScreen._textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
