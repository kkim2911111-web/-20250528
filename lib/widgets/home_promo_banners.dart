import 'package:flutter/material.dart';

import '../screens/coupon_screen.dart';
import '../screens/point_screen.dart';

/// 홈 — 일반 렌트 문의 카드 아래 쿠폰·포인트 프로모 배너 (가로 2열)
class HomePromoBannersRow extends StatelessWidget {
  const HomePromoBannersRow({super.key});

  static const double _gap = 10;
  static const double _minHeight = 130;
  static const double _radius = 14;

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

  static const _bg = Color(0xFF12122A);
  static const _gold = Color(0xFFD4AF37);
  static const _goldMuted = Color(0xFFB8962E);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HomePromoBannersRow._radius),
        child: Ink(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HomePromoBannersRow._minHeight,
            ),
            child: ClipPath(
              clipper: _TicketBannerClipper(
                radius: HomePromoBannersRow._radius,
                notchRadius: 7,
              ),
              child: Stack(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(color: _bg),
                    child: SizedBox.expand(),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TicketDashedDividerPainter(
                        lineColor: _gold.withValues(alpha: 0.35),
                        dashFractionFromLeft: 0.58,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PromoTag(
                          label: '신규가입',
                          background: _gold.withValues(alpha: 0.18),
                          foreground: _gold,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '첫 1시간\n무료쿠폰!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '5,000원 즉시지급',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 10,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              '쿠폰 받기 →',
                              style: TextStyle(
                                color: _gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.confirmation_number_outlined,
                              size: 18,
                              color: _goldMuted.withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

  static const _bg = Color(0xFFF0FAF4);
  static const _border = Color(0xFFC0DD97);
  static const _green = Color(0xFF3B6D11);
  static const _greenTag = Color(0xFF4A7C1C);

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
            border: Border.all(color: _border, width: 1.5),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HomePromoBannersRow._minHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PromoTag(
                    label: '포인트 적립',
                    background: _border.withValues(alpha: 0.55),
                    foreground: _greenTag,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '탈 때마다\n5% 돌아와요',
                    style: TextStyle(
                      color: _green,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '대여 완료하면 포인트 자동 적립!',
                    style: TextStyle(
                      color: _green.withValues(alpha: 0.72),
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Spacer(),
                  Row(
                    children: [
                      const Text(
                        '내 포인트 →',
                        style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.savings_outlined,
                        size: 18,
                        color: _green.withValues(alpha: 0.35),
                      ),
                    ],
                  ),
                ],
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 좌·우 티켓 노치 (반원 홈)
class _TicketBannerClipper extends CustomClipper<Path> {
  final double radius;
  final double notchRadius;

  const _TicketBannerClipper({
    required this.radius,
    required this.notchRadius,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final path = Path();

    path.moveTo(radius, 0);
    path.lineTo(w - radius, 0);
    path.arcToPoint(
      Offset(w, radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(w, cy - notchRadius);
    path.arcToPoint(
      Offset(w - notchRadius * 2, cy),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.arcToPoint(
      Offset(w, cy + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(w, h - radius);
    path.arcToPoint(
      Offset(w - radius, h),
      radius: Radius.circular(radius),
    );
    path.lineTo(radius, h);
    path.arcToPoint(
      Offset(0, h - radius),
      radius: Radius.circular(radius),
    );
    path.lineTo(0, cy + notchRadius);
    path.arcToPoint(
      Offset(notchRadius * 2, cy),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.arcToPoint(
      Offset(0, cy - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(0, radius);
    path.arcToPoint(
      Offset(radius, 0),
      radius: Radius.circular(radius),
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _TicketBannerClipper oldClipper) {
    return oldClipper.radius != radius ||
        oldClipper.notchRadius != notchRadius;
  }
}

/// 티켓 점선 구분선
class _TicketDashedDividerPainter extends CustomPainter {
  final Color lineColor;
  final double dashFractionFromLeft;

  const _TicketDashedDividerPainter({
    required this.lineColor,
    required this.dashFractionFromLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * dashFractionFromLeft;
    const dashHeight = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    var y = 14.0;
    while (y < size.height - 14) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TicketDashedDividerPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.dashFractionFromLeft != dashFractionFromLeft;
  }
}
