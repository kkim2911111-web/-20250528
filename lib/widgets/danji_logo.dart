import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 단지카 브랜드 로고 (SVG)
enum DanjiLogoVariant {
  /// 파란 라운드 배경 포함 (스플래시·로그인)
  full,

  /// 차량 아이콘만 (앱바 등)
  iconOnly,
}

class DanjiLogo extends StatelessWidget {
  final double size;
  final DanjiLogoVariant variant;

  const DanjiLogo({
    super.key,
    required this.size,
    this.variant = DanjiLogoVariant.full,
  });

  static const _fullAsset = 'assets/brand/danji_logo.svg';
  static const _iconAsset = 'assets/brand/danji_logo_icon.svg';

  Widget _iconOnlyFallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF3182F6),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.directions_car,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = variant == DanjiLogoVariant.full ? _fullAsset : _iconAsset;
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticsLabel: variant == DanjiLogoVariant.full
            ? '단지카 로고'
            : '단지카 아이콘',
        errorBuilder: variant == DanjiLogoVariant.iconOnly
            ? (_, __, ___) => _iconOnlyFallback()
            : null,
      ),
    );
  }
}
