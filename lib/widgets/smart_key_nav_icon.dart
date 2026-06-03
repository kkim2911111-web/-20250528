import 'package:flutter/material.dart';

/// 하단 네비 — 스마트키 탭 커스텀 아이콘 (열쇠 링 + 플러스)
class SmartKeyNavIcon extends StatelessWidget {
  static const _activeBlue = Color(0xFF3182F6);
  static const _inactiveGray = Color(0xFFBBBBBB);

  final bool selected;

  const SmartKeyNavIcon({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _activeBlue : _inactiveGray;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(22, 22),
          painter: _SmartKeyGlyphPainter(color: color),
        ),
        const SizedBox(height: 4),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: selected ? _activeBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _SmartKeyGlyphPainter extends CustomPainter {
  final Color color;

  _SmartKeyGlyphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawCircle(const Offset(8, 12), 4, stroke);
    canvas.drawLine(const Offset(12, 12), const Offset(20, 12), stroke);
    canvas.drawLine(const Offset(17, 10), const Offset(17, 14), stroke);
  }

  @override
  bool shouldRepaint(covariant _SmartKeyGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
