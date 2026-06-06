import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 관리자 화면 공통 Scaffold — 하단 시스템 네비게이션바 영역 확보
class AdminScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  /// AppBar 없는 루트 화면(대시보드 등)은 true
  final bool safeTop;

  const AdminScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.safeTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: backgroundColor ?? DanjiColors.background,
      appBar: appBar,
      floatingActionButtonLocation: floatingActionButtonLocation,
      floatingActionButton: floatingActionButton != null
          ? Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: floatingActionButton,
            )
          : null,
      body: SafeArea(
        top: safeTop,
        bottom: true,
        child: body,
      ),
    );
  }
}
