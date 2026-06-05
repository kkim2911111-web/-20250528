import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/section_card.dart';
import 'admin_complex_info_screen.dart';
import 'admin_license_review_screen.dart';
import 'admin_management_screens.dart';
import 'admin_reservation_list_screen.dart';
import 'admin_vehicle_form_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

abstract final class _DashboardUiColors {
  static const totalBlue = Color(0xFF3182F6);
  static const availableGreen = Color(0xFF22C55E);
  static const inUseOrange = Color(0xFFF97316);
  static const todayPurple = Color(0xFFA855F7);
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _admin = AdminService();
  final _auth = AuthService();
  final _won = NumberFormat('#,###');

  Future<BranchStats>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _statsFuture = _admin.fetchBranchStats(widget.profile.complexId);
    });
  }

  Future<void> _logout() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    final complexName = profile.complexName?.trim().isNotEmpty == true
        ? profile.complexName!.trim()
        : '단지';

    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: DanjiColors.buttonBlue,
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          complexName,
                          style: const TextStyle(
                            color: DanjiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<BranchStats>(
                future: _statsFuture,
                builder: (context, snap) {
                  final stats = snap.data ?? BranchStats.empty;
                  return Row(
                    children: [
                      Expanded(
                        child: _CompactStatCard(
                          label: '전체',
                          value: '${stats.totalVehicles}',
                          icon: Icons.directions_car_outlined,
                          color: _DashboardUiColors.totalBlue,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactStatCard(
                          label: '가용',
                          value: '${stats.availableVehicles.clamp(0, 999)}',
                          icon: Icons.check_circle_outline,
                          color: _DashboardUiColors.availableGreen,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactStatCard(
                          label: '대여중',
                          value: '${stats.inOperation}',
                          icon: Icons.navigation_outlined,
                          color: _DashboardUiColors.inUseOrange,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _CompactStatCard(
                          label: '오늘예약',
                          value: '${stats.todayReservations}',
                          icon: Icons.calendar_today_outlined,
                          color: _DashboardUiColors.todayPurple,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Text(
                      '이번 달 매출',
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    FutureBuilder<BranchStats>(
                      future: _statsFuture,
                      builder: (context, snap) {
                        final amount = snap.data?.monthSales ?? 0;
                        return Text(
                          '₩${_won.format(amount)}',
                          style: const TextStyle(
                            color: DanjiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
            _MenuTile(
              icon: Icons.apartment_outlined,
              title: '단지 정보',
              subtitle: '업체명·사업자등록번호·주소·대표자',
              onTap: () => _open(AdminComplexInfoScreen(profile: profile)),
            ),
            _MenuTile(
              icon: Icons.badge_outlined,
              title: '면허 심사',
              subtitle: '입주민 면허증 승인·거절',
              onTap: () => _open(AdminLicenseReviewScreen(profile: profile)),
            ),
            _MenuTile(
              icon: Icons.event_note_outlined,
              title: '예약 관리',
              subtitle: '예약 목록, 충돌 위험 확인',
              onTap: () => _open(const AdminReservationListScreen()),
            ),
            _MenuTile(
              icon: Icons.fact_check_outlined,
              title: '반납 검수',
              subtitle: '반납 차량 파손 확인, 면책금 청구',
              onTap: () => _open(
                AdminReturnInspectionScreen(profile: profile),
              ),
            ),
            _MenuTile(
              icon: Icons.map_outlined,
              title: '차량 위치',
              subtitle: '대여 중인 차량 실시간 위치 확인',
              onTap: () => _open(AdminVehicleLocationScreen(profile: profile)),
            ),
            _MenuTile(
              icon: Icons.directions_car_outlined,
              title: '차량 관리',
              subtitle: '차량 등록, 상태 변경',
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AdminVehicleManageScreen(profile: profile),
                  ),
                );
                if (changed == true) _reload();
              },
            ),
            _MenuTile(
              icon: Icons.verified_user_outlined,
              title: '보험 관리',
              subtitle: '차량별 보험 등록, 만료 현황',
              onTap: () => _open(AdminInsuranceScreen(profile: profile)),
            ),
            _MenuTile(
              icon: Icons.sell_outlined,
              title: '가격 관리',
              subtitle: '차량별 시간당 가격 설정',
              onTap: () => _open(AdminPriceScreen(profile: profile)),
            ),
            _MenuTile(
              icon: Icons.bar_chart_outlined,
              title: '매출 관리',
              subtitle: '등록 차량별 매출·예약 현황',
              onTap: () => _open(AdminSalesScreen(profile: profile)),
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
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _CompactStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _CompactStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
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
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
          trailing: const Icon(Icons.chevron_right, color: DanjiColors.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}
