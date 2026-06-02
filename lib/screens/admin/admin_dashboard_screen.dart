import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/section_card.dart';
import 'admin_license_review_screen.dart';
import 'admin_management_screens.dart';
import 'admin_vehicle_form_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminDashboardScreen({super.key, required this.profile});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _admin = AdminService();
  final _auth = AuthService();
  final _won = NumberFormat('#,###');

  Future<BranchStats>? _statsFuture;
  Future<List<AdminVehicleDetail>>? _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _statsFuture = _admin.fetchBranchStats(widget.profile.complexId);
      _vehiclesFuture = _admin.fetchVehicles(widget.profile.complexId);
    });
  }

  String _complexLabel(AdminVehicleDetail vehicle) {
    final name = vehicle.complexName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final fallback = widget.profile.complexName?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return '단지';
  }

  Future<void> _logout() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '지점 관리',
          style: TextStyle(
            color: DanjiColors.buttonBlue,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('로그아웃'),
            style: TextButton.styleFrom(foregroundColor: DanjiColors.textSecondary),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: () async => _reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text(
              '지점 현황',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${profile.displayName}님의 지점 · ${profile.complexName ?? '단지'}',
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FutureBuilder<BranchStats>(
              future: _statsFuture,
              builder: (context, snap) {
                final stats = snap.data ?? BranchStats.empty;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    _StatCard(
                      label: '전체 차량',
                      value: '${stats.totalVehicles}',
                      icon: Icons.directions_car_filled_outlined,
                      color: DanjiColors.buttonBlue,
                    ),
                    _StatCard(
                      label: '가용 차량',
                      value: '${stats.availableVehicles.clamp(0, 999)}',
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF43A047),
                    ),
                    _StatCard(
                      label: '대여 중',
                      value: '${stats.inOperation}',
                      icon: Icons.navigation_outlined,
                      color: const Color(0xFFFB8C00),
                    ),
                    _StatCard(
                      label: '오늘 예약',
                      value: '${stats.todayReservations}',
                      icon: Icons.calendar_today_outlined,
                      color: const Color(0xFF8E24AA),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: DanjiColors.buttonBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '이번 달 매출',
                          style: TextStyle(
                            color: DanjiColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        FutureBuilder<BranchStats>(
                          future: _statsFuture,
                          builder: (context, snap) {
                            final amount = snap.data?.monthSales ?? 0;
                            return Text(
                              '₩${_won.format(amount)}',
                              style: const TextStyle(
                                color: DanjiColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '등록 차량',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AdminVehicleDetail>>(
              future: _vehiclesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SectionCard(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return SectionCard(
                    child: Text(friendlyAdminError(snap.error!)),
                  );
                }
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return const SectionCard(
                    child: Text('등록된 차량이 없습니다. 아래에서 차량을 등록해주세요.'),
                  );
                }
                return Column(
                  children: [
                    for (final v in list.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SectionCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              v.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${_complexLabel(v)} · ${v.vehicleType} · '
                              '${v.carNumber ?? '번호 미등록'}',
                            ),
                            trailing: Icon(
                              v.isAvailable
                                  ? Icons.check_circle
                                  : Icons.pause_circle,
                              color: v.isAvailable
                                  ? const Color(0xFF43A047)
                                  : DanjiColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    if (list.length > 5)
                      Text(
                        '외 ${list.length - 5}대 · 차량 관리에서 전체 보기',
                        style: const TextStyle(
                          color: DanjiColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            const Text(
              '관리 메뉴',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            _MenuTile(
              icon: Icons.badge_outlined,
              title: '면허 심사',
              subtitle: '입주민 면허증 승인·거절',
              onTap: () => _open(AdminLicenseReviewScreen(profile: profile)),
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
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 28,
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
