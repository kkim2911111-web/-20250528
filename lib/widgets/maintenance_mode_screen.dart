import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';

/// 점검모드 — 입주민 전체 화면 안내 (내 예약·반납 진입 허용)
class MaintenanceModeScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onMyReservations;
  final VoidCallback? onReturn;
  final VoidCallback? onRefresh;

  const MaintenanceModeScreen({
    super.key,
    required this.message,
    this.onMyReservations,
    this.onReturn,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: DanjiColors.buttonBlue,
          onRefresh: () async => onRefresh?.call(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            children: [
              const Icon(
                Icons.construction_outlined,
                size: 56,
                color: DanjiColors.textSecondary,
              ),
              const SizedBox(height: 20),
              Text(
                '서비스 점검 중',
                textAlign: TextAlign.center,
                style: DanjiTypography.subtitleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '진행 중인 대여의 반납·연장·내 예약 조회는 이용하실 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DanjiColors.textMuted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),
              if (onMyReservations != null)
                FilledButton.icon(
                  onPressed: onMyReservations,
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('내 예약 보기'),
                ),
              if (onReturn != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onReturn,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('반납하기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
