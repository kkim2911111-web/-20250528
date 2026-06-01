import 'package:flutter/material.dart';

import '../models/my_page_profile.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

/// 운전면허 정보 — 읽기 전용
class LicenseInfoReadOnlyScreen extends StatelessWidget {
  final MyPageProfile profile;

  const LicenseInfoReadOnlyScreen({super.key, required this.profile});

  String get _statusLabel {
    if (!profile.isLicenseComplete) return '미등록';
    if (profile.isLicenseApproved) return '승인 완료';
    if (profile.licenseRejectionReason != null &&
        profile.licenseRejectionReason!.trim().isNotEmpty) {
      return '거절';
    }
    return '심사 중';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(
        title: '운전면허',
        showBack: true,
        light: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const Text(
            '운전면허 정보는 조회만 가능하며 수정할 수 없습니다.\n'
            '변경이 필요하면 고객센터로 문의해주세요.',
            style: TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          _ReadOnlyField(
            label: '면허번호',
            value: profile.licenseNumber?.trim().isNotEmpty == true
                ? profile.licenseNumber!
                : '-',
          ),
          _ReadOnlyField(
            label: '만료일',
            value: profile.licenseExpiry?.trim().isNotEmpty == true
                ? profile.licenseExpiry!
                : '-',
          ),
          _ReadOnlyField(
            label: '승인 상태',
            value: _statusLabel,
            valueColor: profile.isLicenseApproved
                ? DanjiColors.buttonBlue
                : DanjiColors.textPrimary,
          ),
          if (profile.licenseRejectionReason != null &&
              profile.licenseRejectionReason!.trim().isNotEmpty)
            _ReadOnlyField(
              label: '거절 사유',
              value: profile.licenseRejectionReason!.trim(),
              valueColor: DanjiColors.accentRed,
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
