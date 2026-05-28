import 'package:flutter/material.dart';

class DanjiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? extraActions;
  final bool showBack;
  final bool showHome;
  final VoidCallback? onHome;

  const DanjiAppBar({
    super.key,
    required this.title,
    this.extraActions,
    this.showBack = true,
    this.showHome = true,
    this.onHome,
  });

  static const bg = Color(0xFF071826);
  static const fg = Color(0xFFEAF2FF);

  void _goHome(BuildContext context) {
    if (onHome != null) {
      onHome!();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showHomeButton = showHome && (canPop || onHome != null);

    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: showBack && canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '뒤로가기',
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      title: Text(title),
      actions: [
        if (showHomeButton)
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: '홈',
            onPressed: () => _goHome(context),
          ),
        ...?extraActions,
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
