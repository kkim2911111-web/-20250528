import 'package:flutter/material.dart';

import '../screens/support_pages.dart';
import '../theme/danji_colors.dart';

/// 회원가입 — 약관·마케팅 동의 체크박스
class TermsConsentSection extends StatelessWidget {
  final bool agreeTerms;
  final bool agreePrivacy;
  final bool agreeMarketing;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onPrivacyChanged;
  final ValueChanged<bool> onMarketingChanged;

  const TermsConsentSection({
    super.key,
    required this.agreeTerms,
    required this.agreePrivacy,
    required this.agreeMarketing,
    required this.onTermsChanged,
    required this.onPrivacyChanged,
    required this.onMarketingChanged,
  });

  void _openPolicy(BuildContext context, int tabIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TermsPolicyScreen(initialTabIndex: tabIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConsentRow(
          value: agreeTerms,
          onChanged: onTermsChanged,
          label: '[필수] 이용약관에 동의합니다',
          onView: () => _openPolicy(context, 0),
        ),
        _ConsentRow(
          value: agreePrivacy,
          onChanged: onPrivacyChanged,
          label: '[필수] 개인정보 처리방침에 동의합니다',
          onView: () => _openPolicy(context, 1),
        ),
        _ConsentRow(
          value: agreeMarketing,
          onChanged: onMarketingChanged,
          label: '[선택] 마케팅 수신에 동의합니다',
          required: false,
        ),
      ],
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final VoidCallback? onView;
  final bool required;

  const _ConsentRow({
    required this.value,
    required this.onChanged,
    required this.label,
    this.onView,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: DanjiColors.buttonBlue,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              behavior: HitTestBehavior.opaque,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: required
                      ? DanjiColors.textPrimary
                      : DanjiColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (onView != null)
            TextButton(
              onPressed: onView,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '보기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DanjiColors.buttonBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
