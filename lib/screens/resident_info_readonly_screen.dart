import 'package:flutter/material.dart';

import '../models/my_page_profile.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

/// 입주민 인증 정보 — 읽기 전용
class ResidentInfoReadOnlyScreen extends StatelessWidget {
  final MyPageProfile profile;

  const ResidentInfoReadOnlyScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(
        title: '주민인증',
        showBack: true,
        light: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const Text(
            '입주민 인증 정보는 가입 시 등록되며 수정할 수 없습니다.\n'
            '변경이 필요하면 고객센터로 문의해주세요.',
            style: TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          _ReadOnlyField(
            label: '아파트',
            value: profile.residentComplexName ?? '-',
          ),
          _ReadOnlyField(
            label: '동/호',
            value: profile.dongHoLabel ?? '-',
          ),
          _ReadOnlyField(
            label: '인증 상태',
            value: profile.isResidentComplete
                ? '인증완료'
                : profile.hasResidentRegistration
                    ? '승인대기'
                    : '미등록',
            valueColor: profile.isResidentComplete
                ? DanjiColors.buttonBlue
                : profile.hasResidentRegistration
                    ? DanjiColors.accentRed
                    : DanjiColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: DanjiColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? DanjiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
