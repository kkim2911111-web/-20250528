import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/license_review_item.dart';
import '../../models/resident_review_item.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../services/admin_notification_navigation.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/logout_confirm_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/section_card.dart';
import '../notification_list_screen.dart';
import '../../utils/vehicle_insurance_status.dart';
import 'admin_complex_info_screen.dart';
import 'admin_customer_hub_screen.dart';
import 'admin_management_screens.dart';
import 'admin_notice_screen.dart';
import 'admin_reservation_list_screen.dart';
import 'admin_vehicle_form_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

abstract final class _DashboardUiColors {
  static const availableGreen = Color(0xFF22C55E);
  static const inUseOrange = Color(0xFFF97316);
  static const todayPurple = Color(0xFFA855F7);
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _admin = AdminService();
  final _auth = AuthService.instance;
  final _won = NumberFormat('#,###');
  final _dateLineFormat = DateFormat('M월 d일 (E)', 'ko_KR');
  final _dateTimeFormat = DateFormat('M/d HH:mm');

  Future<BranchStats>? _statsFuture;
  Future<int>? _conflictFuture;
  Future<List<AdminVehicleDashboardCard>>? _vehicleCardsFuture;
  Future<_DashboardBadges>? _badgesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final complexId = widget.profile.complexId;
    setState(() {
      _statsFuture = _admin.fetchBranchStats(complexId);
      _conflictFuture = _admin.fetchConflictRiskCount();
      _vehicleCardsFuture = _admin.fetchVehicleDashboardCards(complexId);
      _badgesFuture = _loadBadges(complexId);
    });
  }

  Future<_DashboardBadges> _loadBadges(String complexId) async {
    final results = await Future.wait([
      _admin.fetchLicenseReviews(),
      _admin.fetchResidentReviews(),
      _admin.fetchReturnInspections(complexId, status: 'returned'),
      _admin.fetchVehicles(complexId),
    ]);
    final licenses = results[0] as List<LicenseReviewItem>;
    final residentReviews = results[1] as List<ResidentReviewItem>;
    final inspections = results[2] as List;
    final vehicles = results[3] as List<AdminVehicleDetail>;

    final licensePending =
        licenses.where((e) => e.isPendingReview).length;
    final residentReviewPending = residentReviews.length;
    final insuranceLevel = VehicleInsuranceStatus.menuBadgeLevel(
      vehicles.map((v) => v.insuranceExpiresAt),
    );

    return _DashboardBadges(
      licensePending: licensePending,
      residentReviewPending: residentReviewPending,
      inspectionPending: inspections.length,
      insuranceLevel: insuranceLevel,
    );
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!confirmed || !mounted) return;
    await _auth.signOut();
  }

  void _openNotifications() {
    final profile = widget.profile;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationListScreen(
          onlyOwnRows: true,
          onNotificationTap: (ctx, item) async {
            AdminNotificationNavigation.openFromInbox(
              ctx,
              item: item,
              staffProfile: profile,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    final complexName = profile.complexName?.trim().isNotEmpty == true
        ? profile.complexName!.trim()
        : '단지';

    return AdminScaffold(
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        foregroundColor: DanjiColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              complexName,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.2,
              ),
            ),
            Text(
              profile.displayName,
              style: const TextStyle(
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
        onRefresh: () async => _reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              FutureBuilder<BranchStats>(
                future: _statsFuture,
                builder: (context, snap) {
                  final stats = snap.data ?? BranchStats.empty;
                  final dateLabel = _dateLineFormat.format(DateTime.now());
                  return SectionCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$dateLabel  |  오늘 ₩${_won.format(stats.todaySales)}',
                            style: const TextStyle(
                              color: DanjiColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _open(AdminSalesScreen(profile: profile)),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              '이번달 ₩${_won.format(stats.monthSales)}',
                              style: const TextStyle(
                                color: DanjiColors.buttonBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              FutureBuilder<BranchStats>(
                future: _statsFuture,
                builder: (context, snap) {
                  final stats = snap.data ?? BranchStats.empty;
                  return Row(
                    children: [
                      Expanded(
                        child: _CompactStatCard(
                          label: '오늘예약',
                          value: '${stats.todayReservations}',
                          icon: Icons.calendar_today_outlined,
                          color: _DashboardUiColors.todayPurple,
                          onTap: () => _open(
                            const AdminReservationListScreen(
                              openTodayDayFilter: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactStatCard(
                          label: '대여중',
                          value: '${stats.inOperation}',
                          icon: Icons.navigation_outlined,
                          color: _DashboardUiColors.inUseOrange,
                          onTap: () => _open(
                            const AdminReservationListScreen(openInUseTab: true),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactStatCard(
                          label: '가용',
                          value: '${stats.availableVehicles.clamp(0, 999)}',
                          icon: Icons.check_circle_outline,
                          color: _DashboardUiColors.availableGreen,
                          onTap: () => _openVehicleManage(),
                        ),
                      ),
                    ],
                  );
                },
              ),
              FutureBuilder<int>(
                future: _conflictFuture,
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  if (count <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ConflictWarningCard(
                      count: count,
                      onTap: () => _open(
                        const AdminReservationListScreen(
                          openConflictTab: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<AdminVehicleDashboardCard>>(
                future: _vehicleCardsFuture,
                builder: (context, snap) {
                  final cards = snap.data ?? const [];
                  if (cards.isEmpty) return const SizedBox.shrink();
                  return _VehicleSwipeCards(
                    cards: cards,
                    dateTimeFormat: _dateTimeFormat,
                  );
                },
              ),
              const SizedBox(height: 20),
            const Text(
              '관리 메뉴',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<_DashboardBadges>(
              future: _badgesFuture,
              builder: (context, badgeSnap) {
                final badges = badgeSnap.data ?? _DashboardBadges.empty;
                return Column(
                  children: [
                    _MenuTile(
                      icon: Icons.campaign_outlined,
                      title: '공지사항',
                      subtitle: '단지·전체 공지 등록·수정',
                      onTap: () => _open(AdminNoticeScreen(profile: profile)),
                    ),
                    _MenuTile(
                      icon: Icons.person_outline,
                      title: '내정보',
                      subtitle: '업체명·사업자등록번호·주소·대표자',
                      onTap: () =>
                          _open(AdminComplexInfoScreen(profile: profile)),
                    ),
                    _MenuTile(
                      icon: Icons.people_outline,
                      title: '고객관리',
                      subtitle: '입주민·면허심사·이용이력·블랙리스트',
                      badgeCount: badges.customerHubPendingCount,
                      onTap: () =>
                          _open(AdminCustomerHubScreen(profile: profile)),
                    ),
                    _MenuTile(
                      icon: Icons.event_note_outlined,
                      title: '대여관리',
                      subtitle: '목록/타임라인, 충돌 위험 확인',
                      onTap: () => _open(const AdminReservationListScreen()),
                    ),
                    _MenuTile(
                      icon: Icons.fact_check_outlined,
                      title: '반납검수',
                      subtitle: '반납 차량 파손 확인, 면책금 청구',
                      badgeCount: badges.inspectionPending,
                      onTap: () => _open(
                        AdminReturnInspectionScreen(profile: profile),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.directions_car_outlined,
                      title: '차량관리',
                      subtitle: '차량·위치·가격·보험 통합 관리',
                      badgeLabel: VehicleInsuranceStatus.menuBadgeLabel(
                        badges.insuranceLevel,
                      ).isEmpty
                          ? null
                          : VehicleInsuranceStatus.menuBadgeLabel(
                              badges.insuranceLevel,
                            ),
                      badgeColor: badges.insuranceLevel ==
                              VehicleInsuranceMenuBadgeLevel.none
                          ? null
                          : VehicleInsuranceStatus.menuBadgeColor(
                              badges.insuranceLevel,
                            ),
                      onTap: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                AdminVehicleManageScreen(profile: profile),
                          ),
                        );
                        if (changed == true) _reload();
                      },
                    ),
                    _MenuTile(
                      icon: Icons.bar_chart_outlined,
                      title: '매출관리',
                      subtitle: '등록 차량별 매출·예약 현황',
                      onTap: () => _open(AdminSalesScreen(profile: profile)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AdminVehicleFormScreen(profile: profile),
                  ),
                );
                if (created == true) _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('차량 등록'),
              style: FilledButton.styleFrom(
                backgroundColor: DanjiColors.buttonBlue,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openVehicleManage() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminVehicleManageScreen(profile: widget.profile),
      ),
    );
    if (changed == true) _reload();
  }
}

class _VehicleSwipeCards extends StatelessWidget {
  final List<AdminVehicleDashboardCard> cards;
  final DateFormat dateTimeFormat;

  const _VehicleSwipeCards({
    required this.cards,
    required this.dateTimeFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '차량 현황',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(
          height: 148,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.88),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _VehicleStatusCard(
                  card: card,
                  dateTimeFormat: dateTimeFormat,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VehicleStatusCard extends StatelessWidget {
  final AdminVehicleDashboardCard card;
  final DateFormat dateTimeFormat;

  const _VehicleStatusCard({
    required this.card,
    required this.dateTimeFormat,
  });

  Color get _statusColor {
    switch (card.status) {
      case AdminVehicleDashboardStatus.inUse:
        return _DashboardUiColors.inUseOrange;
      case AdminVehicleDashboardStatus.waitingPayment:
        return _DashboardUiColors.todayPurple;
      case AdminVehicleDashboardStatus.available:
        return _DashboardUiColors.availableGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plate = card.carNumber?.trim().isNotEmpty == true
        ? card.carNumber!.trim()
        : '번호 미등록';

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.vehicleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plate,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (card.status == AdminVehicleDashboardStatus.available)
            const Text(
              '현재 대여 가능',
              style: TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            )
          else ...[
            Text(
              '임차인: ${card.renterName ?? '—'}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              card.status == AdminVehicleDashboardStatus.inUse
                  ? '대여 ${card.periodStart != null ? dateTimeFormat.format(card.periodStart!) : '-'}'
                    ' · 반납예정 ${card.periodEnd != null ? dateTimeFormat.format(card.periodEnd!) : '-'}'
                  : '시작예정 ${card.periodStart != null ? dateTimeFormat.format(card.periodStart!) : '-'}',
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConflictWarningCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ConflictWarningCard({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.danger,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '⚠️ 충돌위험 예약 $count건',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _CompactStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 1.1,
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

class _DashboardBadges {
  final int licensePending;
  final int residentReviewPending;
  final int inspectionPending;
  final VehicleInsuranceMenuBadgeLevel insuranceLevel;

  const _DashboardBadges({
    required this.licensePending,
    required this.residentReviewPending,
    required this.inspectionPending,
    required this.insuranceLevel,
  });

  int get customerHubPendingCount =>
      licensePending + residentReviewPending;

  static const empty = _DashboardBadges(
    licensePending: 0,
    residentReviewPending: 0,
    inspectionPending: 0,
    insuranceLevel: VehicleInsuranceMenuBadgeLevel.none,
  );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badgeCount;
  final String? badgeLabel;
  final Color? badgeColor;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount,
    this.badgeLabel,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final count = badgeCount ?? 0;
    final showCountBadge = count > 0;
    final showLabelBadge =
        badgeLabel != null && badgeLabel!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: DanjiColors.buttonBlue, size: 28),
          title: Text(
            title,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCountBadge)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DanjiColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (showLabelBadge)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ??
                            VehicleInsuranceStatus.expiringWarningColor)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel!,
                    style: TextStyle(
                      color: badgeColor ??
                          VehicleInsuranceStatus.expiringWarningColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, color: DanjiColors.textMuted),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
