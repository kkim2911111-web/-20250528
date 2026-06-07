import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import 'super_admin_common.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  final SuperAdminService service;

  const SuperAdminDashboardScreen({super.key, required this.service});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  Future<SuperAdminDashboard>? _dashFuture;
  Future<List<SuperAdminRevenueRow>>? _revFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _dashFuture = widget.service.fetchDashboard();
      _revFuture = widget.service.fetchRevenue(year: _year, month: _month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: DanjiColors.primaryBlue,
      onRefresh: () async => _reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SuperAdminPeriodFilter(
            year: _year,
            month: _month,
            onYearChanged: (y) {
              setState(() => _year = y);
              _reload();
            },
            onMonthChanged: (m) {
              setState(() => _month = m);
              _reload();
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<SuperAdminDashboard>(
            future: _dashFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Text(friendlySuperAdminError(snap.error!));
              }
              final d = snap.data ?? const SuperAdminDashboard();
              return SuperAdminStatGrid(
                items: [
                  (label: '단지', value: '${d.complexCount}', color: DanjiColors.primaryBlue),
                  (label: '차량', value: '${d.vehicleCount}', color: const Color(0xFF6366F1)),
                  (label: '가용차량', value: '${d.availableVehicleCount}', color: const Color(0xFF22C55E)),
                  (label: '대여중', value: '${d.inUseVehicleCount}', color: const Color(0xFFF97316)),
                  (label: '스태프', value: '${d.staffApprovedCount}/${d.staffCount}', color: const Color(0xFF8B5CF6)),
                  (label: '입주민', value: '${d.residentApprovedCount}/${d.residentCount}', color: const Color(0xFF14B8A6)),
                  (label: '오늘예약', value: '${d.reservationCountToday}', color: const Color(0xFFA855F7)),
                  (label: '진행예약', value: '${d.reservationActiveCount}', color: DanjiColors.danger),
                  (label: '오늘매출', value: '₩${superAdminWon.format(d.todayRevenue)}', color: DanjiColors.primaryBlue),
                  (label: '이번달', value: '₩${superAdminWon.format(d.monthRevenue)}', color: const Color(0xFF0EA5E9)),
                  (label: '누적매출', value: '₩${superAdminWon.format(d.totalRevenue)}', color: const Color(0xFF1E2A3A)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            '단지별 매출 (선택 월)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<SuperAdminRevenueRow>>(
            future: _revFuture,
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (rows.isEmpty) {
                return const Text('데이터 없음', style: TextStyle(color: DanjiColors.textSecondary));
              }
              return Column(
                children: rows.take(10).map((r) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.complexName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('예약 ${r.reservationCount}건'),
                    trailing: Text(
                      '₩${superAdminWon.format(r.totalRevenue)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
