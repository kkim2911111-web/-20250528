import 'package:flutter/material.dart';

import '../config/kakao_config.dart';
import '../screens/kakao_address_search_screen.dart';
import '../theme/danji_colors.dart';

/// 탭 시 카카오 주소 검색 WebView를 열고 선택 결과를 컨트롤러에 채움
class KakaoAddressField extends StatelessWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? textStyle;
  final int maxLines;
  final EdgeInsetsGeometry? padding;

  const KakaoAddressField({
    super.key,
    required this.controller,
    required this.decoration,
    this.textStyle,
    this.maxLines = 1,
    this.padding,
  });

  Future<void> _openSearch(BuildContext context) async {
    if (!KakaoConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '카카오 JavaScript Key가 설정되지 않았습니다.\n'
            '.env에 KAKAO_JAVASCRIPT_KEY를 추가해주세요.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final selected = await KakaoAddressSearchScreen.show(context);
    if (selected == null || selected.isEmpty) return;
    controller.text = selected;
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      readOnly: true,
      maxLines: maxLines,
      onTap: () => _openSearch(context),
      style: textStyle ??
          const TextStyle(
            color: DanjiColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
      decoration: decoration.copyWith(
        suffixIcon: decoration.suffixIcon ??
            const Icon(Icons.search, color: DanjiColors.textSecondary),
      ),
    );

    if (padding == null) return field;
    return Padding(padding: padding!, child: field);
  }
}
