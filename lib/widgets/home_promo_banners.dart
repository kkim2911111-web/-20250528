import 'package:flutter/material.dart';

import '../screens/coupon_screen.dart';
import '../screens/point_screen.dart';

/// 홈 — 쿠폰·포인트 프로모 카드 (가로 2열)
class HomePromoBannersRow extends StatelessWidget {
  const HomePromoBannersRow({super.key});

  static const double _gap = 10;
  static const double _radius = 14;
  static const EdgeInsets _cardPadding =
      EdgeInsets.fromLTRB(15, 16, 15, 16);

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _CouponPromoBanner(onTap: () => _openCoupons(context))),
          const SizedBox(width: _gap),
          Expanded(child: _PointPromoBanner(onTap: () => _openPoints(context))),
        ],
      ),
    );
  }

  void _openCoupons(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CouponScreen()),
    );
  }

  void _openPoints(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PointScreen()),
    );
  }
}

class _CouponPromoBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CouponPromoBanner({required this.onTap});

  static const _brandBlue = Color(0xFF3182F6);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HomePromoBannersRow._radius),
        child: Ink(
          decoration: BoxDecoration(
            color: _brandBlue,
            borderRadius: BorderRadius.circular(HomePromoBannersRow._radius),
          ),
          child: Padding(
            padding: HomePromoBannersRow._cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PromoTag(
                  label: '신규가입',
                  background: Colors.white.withValues(alpha: 0.25),
                  foreground: Colors.white,
                ),
                const SizedBox(height: 10),
                const Text(
                  '첫 1시간\n무료쿠폰',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '5,000원 즉시지급',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                const Text(
                  '쿠폰 받기 →',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointPromoBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _PointPromoBanner({required this.onTap});

  static const _bg = Color(0xFFEBF4FF);
  static const _border = Color(0xFFB5D4F4);
  static const _titleColor = Color(0xFF0C447C);
  static const _subColor = Color(0xFF185FA5);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HomePromoBannersRow._radius),
        child: Ink(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(HomePromoBannersRow._radius),
            border: Border.all(color: _border, width: 0.5),
          ),
          child: Padding(
            padding: HomePromoBannersRow._cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PromoTag(
                  label: '포인트 적립',
                  background: _border,
                  foreground: _titleColor,
                ),
                const SizedBox(height: 10),
                const Text(
                  '탈 때마다\n5% 적립',
                  style: TextStyle(
                    color: _titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '대여 완료 시 자동',
                  style: TextStyle(
                    color: _subColor,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                const Text(
                  '내 포인트 →',
                  style: TextStyle(
                    color: _subColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoTag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _PromoTag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}
