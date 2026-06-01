import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';

/// 앱바·헤더용 단지카 로고 (아이콘 + 텍스트)
class DanjiBrandTitle extends StatelessWidget {
  final double iconSize;
  final double fontSize;
  final Color? color;
  final FontWeight fontWeight;

  const DanjiBrandTitle({
    super.key,
    this.iconSize = 26,
    this.fontSize = 22,
    this.color,
    this.fontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? DanjiColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.apartment_rounded, color: DanjiColors.brandBlue, size: iconSize),
        const SizedBox(width: 6),
        Text(
          '단지카',
          style: DanjiTypography.headline.copyWith(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: fg,
          ),
        ),
      ],
    );
  }
}
