import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import 'super_admin_coupons_screen.dart';
import 'super_admin_dashboard_screen.dart';
import 'super_admin_entity_screens.dart';
import 'super_admin_reservations_screen.dart';
import 'super_admin_revenue_screen.dart';
import 'super_admin_system_screen.dart';

enum SuperAdminMenu {
  dashboard,
  complexes,
  vehicles,
  staff,
  residents,
  coupons,
  reservations,
  revenue,
  system,
}

class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  SuperAdminMenu _menu = SuperAdminMenu.dashboard;
  final _service = SuperAdminService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2A3A),
        foregroundColor: Colors.white,
        title: const Text(
          '단지카 최고관리자',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => AuthService.instance.signOut(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF1E2A3A)),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  '플랫폼 관리',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            ..._drawerItems(),
          ],
        ),
      ),
      body: _body(),
    );
  }

  List<Widget> _drawerItems() {
    const items = <(SuperAdminMenu, IconData, String)>[
      (SuperAdminMenu.dashboard, Icons.dashboard_outlined, '대시보드'),
      (SuperAdminMenu.complexes, Icons.apartment_outlined, '단지 관리'),
      (SuperAdminMenu.vehicles, Icons.directions_car_outlined, '차량 관리'),
      (SuperAdminMenu.staff, Icons.badge_outlined, '스태프 관리'),
      (SuperAdminMenu.residents, Icons.people_outline, '입주민 관리'),
      (SuperAdminMenu.coupons, Icons.confirmation_number_outlined, '쿠폰 관리'),
      (SuperAdminMenu.reservations, Icons.event_note_outlined, '전체 예약'),
      (SuperAdminMenu.revenue, Icons.payments_outlined, '정산 관리'),
      (SuperAdminMenu.system, Icons.settings_outlined, '시스템'),
    ];
    return items
        .map(
          (e) => ListTile(
            leading: Icon(
              e.$2,
              color: _menu == e.$1
                  ? DanjiColors.primaryBlue
                  : DanjiColors.textSecondary,
            ),
            title: Text(
              e.$3,
              style: TextStyle(
                fontWeight:
                    _menu == e.$1 ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            selected: _menu == e.$1,
            onTap: () {
              Navigator.pop(context);
              setState(() => _menu = e.$1);
            },
          ),
        )
        .toList();
  }

  Widget _body() {
    switch (_menu) {
      case SuperAdminMenu.dashboard:
        return SuperAdminDashboardScreen(service: _service);
      case SuperAdminMenu.complexes:
        return SuperAdminComplexesScreen(service: _service);
      case SuperAdminMenu.vehicles:
        return SuperAdminVehiclesScreen(service: _service);
      case SuperAdminMenu.staff:
        return SuperAdminStaffScreen(service: _service);
      case SuperAdminMenu.residents:
        return SuperAdminResidentsScreen(service: _service);
      case SuperAdminMenu.coupons:
        return SuperAdminCouponsScreen(service: _service);
      case SuperAdminMenu.reservations:
        return SuperAdminReservationsScreen(service: _service);
      case SuperAdminMenu.revenue:
        return SuperAdminRevenueScreen(service: _service);
      case SuperAdminMenu.system:
        return SuperAdminSystemScreen(service: _service);
    }
  }
}
