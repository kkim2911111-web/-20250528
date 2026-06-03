import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/smart_key_nav_icon.dart';
import 'home_screen.dart';
import 'my_page_screen.dart';
import 'smart_key_screen.dart';

/// 하단 탭바 메인 셸 (홈 · 스마트키 · 마이페이지)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _smartKeyKey = GlobalKey<SmartKeyScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            key: _homeKey,
            onGoMyPage: () => setState(() => _index = 2),
          ),
          SmartKeyScreen(
            key: _smartKeyKey,
            isActive: _index == 1,
          ),
          const MyPageScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: DanjiColors.surface,
          border: Border(top: BorderSide(color: DanjiColors.border)),
        ),
        child: NavigationBar(
          backgroundColor: DanjiColors.surface,
          indicatorColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (i == 0) _homeKey.currentState?.reload();
              if (i == 1) _smartKeyKey.currentState?.reload();
            });
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const _ShellNavIcon(
                outlinedIcon: Icons.home_outlined,
                filledIcon: Icons.home,
                selected: false,
              ),
              selectedIcon: const _ShellNavIcon(
                outlinedIcon: Icons.home_outlined,
                filledIcon: Icons.home,
                selected: true,
              ),
              label: '홈',
            ),
            NavigationDestination(
              icon: const SmartKeyNavIcon(selected: false),
              selectedIcon: const SmartKeyNavIcon(selected: true),
              label: '스마트키',
            ),
            NavigationDestination(
              icon: const _ShellNavIcon(
                outlinedIcon: Icons.person_outline,
                filledIcon: Icons.person,
                selected: false,
              ),
              selectedIcon: const _ShellNavIcon(
                outlinedIcon: Icons.person_outline,
                filledIcon: Icons.person,
                selected: true,
              ),
              label: '마이페이지',
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellNavIcon extends StatelessWidget {
  static const _activeBlue = Color(0xFF3182F6);
  static const _inactiveGray = Color(0xFFBBBBBB);

  final IconData outlinedIcon;
  final IconData filledIcon;
  final bool selected;

  const _ShellNavIcon({
    required this.outlinedIcon,
    required this.filledIcon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _activeBlue : _inactiveGray;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? filledIcon : outlinedIcon,
          size: 22,
          color: color,
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
