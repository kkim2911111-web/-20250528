import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/auth_service.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../services/admin_notification_navigation.dart';
import '../../utils/super_admin_settlement_dashboard.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/logout_confirm_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/section_card.dart';
import '../notification_list_screen.dart';
import 'super_admin_common.dart';
import 'super_admin_coupons_screen.dart';
import 'super_admin_entity_screens.dart';
import 'super_admin_nav.dart';
import 'super_admin_reservations_screen.dart';
import 'super_admin_platform_fee_screen.dart';
import 'super_admin_revenue_screen.dart';
import 'super_admin_system_screen.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _service = SuperAdminService();
  final _auth = AuthService.instance;

  SuperAdminDashboard _dashboard = const SuperAdminDashboard();
  SuperAdminSettlementDashboardCard _settlementCard =
      const SuperAdminSettlementDashboardCard(
    year: 0,
    month: 0,
    kind: SuperAdminSettlementDashboardKind.complete,
  );
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final months = superAdminSettlementScanMonths();
      final results = await Future.wait([
        _service.fetchDashboard(),
        ...months.map(
          (m) => _service.fetchRevenue(year: m.year, month: m.month),
        ),
      ]);
      if (!mounted) return;
      final snapshots = <SuperAdminMonthlyRevenueSnapshot>[];
      for (var i = 0; i < months.length; i++) {
        snapshots.add((
          year: months[i].year,
          month: months[i].month,
          rows: results[i + 1] as List<SuperAdminRevenueRow>,
        ));
      }
      setState(() {
        _dashboard = results[0] as SuperAdminDashboard;
        _settlementCard =
            SuperAdminSettlementDashboardCard.fromMonthlySnapshots(snapshots);
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) _reload();
    });
  }

  void _openVehicles({SuperAdminVehicleFilter filter = SuperAdminVehicleFilter.all}) {
    _open(SuperAdminVehiclesScreen(service: _service, initialFilter: filter));
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!confirmed || !mounted) return;
    await _auth.signOut();
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationListScreen(
          onlyOwnRows: true,
          onNotificationTap: (ctx, item) async {
            AdminNotificationNavigation.openFromInbox(
              ctx,
              item: item,
              isSuperAdmin: true,
              superAdminService: _service,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        foregroundColor: DanjiColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '단지카 플랫폼',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.2,
              ),
            ),
            Text(
              '최고관리자',
              style: TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          NotificationBellButton(
            onlyOwnRows: true,
            onPressed: _openNotifications,
          ),
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('로그아웃'),
            style: TextButton.styleFrom(
              foregroundColor: DanjiColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                '${superAdminDateLine.format(DateTime.now())}  |  '
                '오늘 매출 ₩${superAdminWon.format(_dashboard.todayRevenue)}',
                style: const TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: DanjiColors.buttonBlue),
                ),
              )
            else if (_loadError != null)
              Text(friendlySuperAdminError(_loadError!))
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '단지',
                          value: '${_dashboard.complexCount}',
                          icon: Icons.apartment_outlined,
                          color: SuperAdminUiColors.totalBlue,
                          onTap: () => _open(SuperAdminComplexesScreen(service: _service)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '차량',
                          value: '${_dashboard.vehicleCount}',
                          icon: Icons.directions_car_outlined,
                          color: SuperAdminUiColors.totalBlue,
                          onTap: () => _openVehicles(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '가용',
                          value: '${_dashboard.availableVehicleCount}',
                          icon: Icons.check_circle_outline,
                          color: SuperAdminUiColors.availableGreen,
                          onTap: () => _openVehicles(filter: SuperAdminVehicleFilter.available),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '대여중',
                          value: '${_dashboard.inUseVehicleCount}',
                          icon: Icons.navigation_outlined,
                          color: SuperAdminUiColors.inUseOrange,
                          onTap: () => _openVehicles(filter: SuperAdminVehicleFilter.inUse),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '스태프',
                          value: '${_dashboard.staffApprovedCount}/${_dashboard.staffCount}',
                          icon: Icons.badge_outlined,
                          color: SuperAdminUiColors.staffViolet,
                          onTap: () => _open(SuperAdminStaffScreen(service: _service)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '입주민',
                          value: '${_dashboard.residentApprovedCount}/${_dashboard.residentCount}',
                          icon: Icons.people_outline,
                          color: SuperAdminUiColors.residentTeal,
                          onTap: () => _open(SuperAdminResidentsScreen(service: _service)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: '오늘예약',
                          value: '${_dashboard.reservationCountToday}',
                          icon: Icons.calendar_today_outlined,
                          color: SuperAdminUiColors.todayPurple,
                          onTap: () => _open(SuperAdminReservationsScreen(service: _service)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SuperAdminCompactStatCard(
                          label: _settlementCard.label,
                          value: _settlementCard.value,
                          icon: Icons.account_balance_wallet_outlined,
                          color: _settlementCard.color,
                          onTap: () => _open(
                            SuperAdminRevenueScreen(
                              service: _service,
                              initialYear: _settlementCard.year,
                              initialMonth: _settlementCard.month,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SuperAdminMonthlyRevenuePanel(
                    service: _service,
                    onOpenRevenue: () =>
                        _open(SuperAdminRevenueScreen(service: _service)),
                    onOpenPlatformFee: (year, month) => _open(
                      SuperAdminPlatformFeeScreen(
                        service: _service,
                        initialYear: year,
                        initialMonth: month,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const SuperAdminSectionTitle('관리 메뉴'),
            const SizedBox(height: 8),
            SuperAdminMenuTile(
              icon: Icons.apartment_outlined,
              title: '단지 관리',
              subtitle: '단지 등록·수정, 초대코드 발급',
              onTap: () => _open(SuperAdminComplexesScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.directions_car_outlined,
              title: '차량 관리',
              subtitle: '차량 등록, 단지 배정, 가용 상태',
              onTap: () => _openVehicles(),
            ),
            SuperAdminMenuTile(
              icon: Icons.badge_outlined,
              title: '스태프 관리',
              subtitle: '승인·거절, 단지 변경',
              onTap: () => _open(SuperAdminStaffScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.people_outline,
              title: '입주민 관리',
              subtitle: '승인·블랙리스트, 면허 강제 처리',
              onTap: () => _open(SuperAdminResidentsScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.confirmation_number_outlined,
              title: '쿠폰 관리',
              subtitle: '쿠폰 발급·수정·삭제',
              onTap: () => _open(SuperAdminCouponsScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.event_note_outlined,
              title: '전체 예약',
              subtitle: '예약 목록, 강제반납·완료',
              onTap: () => _open(SuperAdminReservationsScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.bar_chart_outlined,
              title: '정산 관리',
              subtitle: '단지별 월매출, 정산완료 처리',
              onTap: () => _open(SuperAdminRevenueScreen(service: _service)),
            ),
            SuperAdminMenuTile(
              icon: Icons.settings_outlined,
              title: '시스템',
              subtitle: '공지·배너·푸시·점검모드',
              onTap: () => _open(SuperAdminSystemScreen(service: _service)),
            ),
          ],
        ),
      ),
    );
  }
}
