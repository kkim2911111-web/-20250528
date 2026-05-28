import 'package:flutter/material.dart';

import 'supabase_client.dart';

class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '(unknown)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('예약'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: () async => supabase.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('로그인: $email'),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('예약 화면 진입 성공'),
                subtitle: Text(
                  '승인된 입주민만 이 화면에 도달합니다. '
                  '차량 목록/예약 생성 UI는 다음 단계에서 확장할 수 있습니다.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
