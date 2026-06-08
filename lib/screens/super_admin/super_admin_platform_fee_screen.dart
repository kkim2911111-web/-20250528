import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminPlatformFeeRow {
  final String complexId;
  final String complexName;
  final int activeVehicleCount;
  final int monthlyFee;

  const SuperAdminPlatformFeeRow({
    required this.complexId,
    required this.complexName,
    required this.activeVehicleCount,
    required this.monthlyFee,
  });
}

class _PlatformFeeSnapshot {
  final List<SuperAdminPlatformFeeRow> rows;
  final int totalFee;

  const _PlatformFeeSnapshot({
    required this.rows,
    required this.totalFee,
  });
}

class SuperAdminPlatformFeeScreen extends StatefulWidget {
  final SuperAdminService service;
  final int? initialYear;
  final int? initialMonth;

  const SuperAdminPlatformFeeScreen({
    super.key,
    required this.service,
    this.initialYear,
    this.initialMonth,
  });

  @override
  State<SuperAdminPlatformFeeScreen> createState() =>
      _SuperAdminPlatformFeeScreenState();
}

class _SuperAdminPlatformFeeScreenState
    extends State<SuperAdminPlatformFeeScreen> {
  late int _year;
  late int _month;
  Future<_PlatformFeeSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.initialYear ?? now.year;
    _month = widget.initialMonth ?? now.month;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _loadSnapshot();
    });
  }

  Future<_PlatformFeeSnapshot> _loadSnapshot() async {
    final results = await Future.wait([
      widget.service.fetchComplexes(),
      widget.service.fetchVehicles(),
    ]);

    final complexes = results[0] as List<SuperAdminComplex>;
    final vehicles = results[1] as List<SuperAdminVehicle>;

    final activeByComplex = <String, int>{};
    for (final vehicle in vehicles) {
      if (!vehicle.isAvailable) continue;
      activeByComplex[vehicle.complexId] =
          (activeByComplex[vehicle.complexId] ?? 0) + 1;
    }

    final rows = complexes
        .map((complex) {
          final count = activeByComplex[complex.id] ?? 0;
          return SuperAdminPlatformFeeRow(
            complexId: complex.id,
            complexName: complex.name,
            activeVehicleCount: count,
            monthlyFee: superAdminPlatformFee(count),
          );
        })
        .toList()
      ..sort((a, b) {
        final byFee = b.monthlyFee.compareTo(a.monthlyFee);
        if (byFee != 0) return byFee;
        return a.complexName.compareTo(b.complexName);
      });

    final totalFee = rows.fold<int>(0, (sum, row) => sum + row.monthlyFee);

    return _PlatformFeeSnapshot(rows: rows, totalFee: totalFee);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '월별 수수료'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SuperAdminMonthFilter(
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
                  onPeriodChanged: (y, m) {
                    setState(() {
                      _year = y;
                      _month = m;
                    });
                    _reload();
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  '운영 차량 수는 현재 등록 기준(is_available) · 대당 월 10만원',
                  style: TextStyle(
                    color: DanjiColors.textMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_PlatformFeeSnapshot>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: DanjiColors.buttonBlue,
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(friendlySuperAdminError(snap.error!)),
                    ),
                  );
                }

                final data = snap.data ??
                    const _PlatformFeeSnapshot(rows: [], totalFee: 0);
                final rows = data.rows;

                if (rows.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      SuperAdminEmptyState('등록된 단지가 없습니다.'),
                    ],
                  );
                }

                return RefreshIndicator(
                  color: DanjiColors.buttonBlue,
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _PlatformFeeCard(row: row);
                    },
                  ),
                );
              },
            ),
          ),
          _PlatformFeeTotalBar(
            year: _year,
            month: _month,
            future: _future,
          ),
        ],
      ),
    );
  }
}

class _PlatformFeeCard extends StatelessWidget {
  final SuperAdminPlatformFeeRow row;

  const _PlatformFeeCard({required this.row});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.complexName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              SuperAdminChip(
                label: '확인중',
                color: DanjiColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: '운영 차량',
            value: '${row.activeVehicleCount}대',
          ),
          const SizedBox(height: 4),
          _InfoLine(
            label: '월 수수료',
            value: '₩${superAdminWon.format(row.monthlyFee)}',
            emphasize: true,
          ),
          const SizedBox(height: 4),
          Text(
            '${row.activeVehicleCount}대 × ₩${superAdminWon.format(superAdminPlatformFeePerVehicle)}',
            style: const TextStyle(
              fontSize: 11,
              color: DanjiColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _InfoLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: DanjiColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 14 : 13,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize
                  ? SuperAdminUiColors.staffViolet
                  : DanjiColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlatformFeeTotalBar extends StatelessWidget {
  final int year;
  final int month;
  final Future<_PlatformFeeSnapshot>? future;

  const _PlatformFeeTotalBar({
    required this.year,
    required this.month,
    required this.future,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: DanjiColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: FutureBuilder<_PlatformFeeSnapshot>(
            future: future,
            builder: (context, snap) {
              final total = snap.data?.totalFee ?? 0;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$year년 $month월 수수료 합계',
                          style: const TextStyle(
                            fontSize: 12,
                            color: DanjiColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₩${superAdminWon.format(total)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: SuperAdminUiColors.staffViolet,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.payments_outlined,
                    color: SuperAdminUiColors.staffViolet,
                    size: 28,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
