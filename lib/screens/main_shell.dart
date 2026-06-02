import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
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
          indicatorColor: DanjiColors.brandBlue.withValues(alpha: 0.1),
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
              icon: Icon(Icons.home_outlined, color: DanjiColors.navUnselected),
              selectedIcon:
                  const Icon(Icons.home, color: DanjiColors.navSelected),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.vpn_key_outlined, color: DanjiColors.navUnselected),
              selectedIcon:
                  const Icon(Icons.vpn_key, color: DanjiColors.navSelected),
              label: '스마트키',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: DanjiColors.navUnselected),
              selectedIcon:
                  const Icon(Icons.person, color: DanjiColors.navSelected),
              label: '마이페이지',
            ),
          ],
        ),
      ),
    );
  }
}
