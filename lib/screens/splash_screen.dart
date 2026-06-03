import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/danji_logo.dart';

/// 앱 시작 스플래시 — 2초 후 child 로 전환
class SplashScreen extends StatefulWidget {
  final Widget child;

  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    return Scaffold(
      backgroundColor: DanjiColors.brandBlue,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DanjiLogo(
                      size: 120,
                      variant: DanjiLogoVariant.full,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '단지카',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Text(
                '우리 아파트 단지의 두 번째 차',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
