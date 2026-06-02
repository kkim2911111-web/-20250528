import 'package:flutter/material.dart';

import '../resident_profile_screen.dart';
import '../screens/main_shell.dart';

/// 입주민 온보딩 완료 후 — 단지 승인 여부에 따라 프로필 또는 메인 앱
class ResidentGate extends StatefulWidget {
  const ResidentGate({super.key});

  @override
  State<ResidentGate> createState() => _ResidentGateState();
}

class _ResidentGateState extends State<ResidentGate> {
  var _retryToken = 0;

  void _retry() => setState(() => _retryToken++);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResidentProfile?>(
      key: ValueKey(_retryToken),
      stream: ResidentRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError && snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('오류')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('입주민 정보 조회 실패: ${snap.error}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retry,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          );
        }

        final profile = snap.data;
        if (profile == null || profile.approved != true) {
          return const ResidentProfileScreen();
        }

        return const MainShell();
      },
    );
  }
}
