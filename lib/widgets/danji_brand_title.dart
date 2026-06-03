import 'package:flutter/material.dart';

import 'danji_logo.dart';

/// 앱바·헤더용 단지카 로고 (SVG 아이콘 + 2줄 타이틀)
class DanjiBrandTitle extends StatelessWidget {
  /// 홈 앱바 높이
  static const double homeToolbarHeight = 64;

  static const Color _primaryBlue = Color(0xFF3182F6);

  const DanjiBrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const DanjiLogo(
          size: 28,
          variant: DanjiLogoVariant.iconOnly,
        ),
        const SizedBox(width: 8),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '단지카',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111111),
                height: 1.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '우리 단지의 두 번째 차',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _primaryBlue,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
