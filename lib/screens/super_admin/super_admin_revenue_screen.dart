import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminRevenueScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminRevenueScreen({super.key, required this.service});
  @override
  State<SuperAdminRevenueScreen> createState() =>
      _SuperAdminRevenueScreenState();
}

class _SuperAdminRevenueScreenState extends State<SuperAdminRevenueScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  Future<List<SuperAdminRevenueRow>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.service.fetchRevenue(year: _year, month: _month);
    });
  }

  Future<void> _exportCsv(List<SuperAdminRevenueRow> rows) async {
    final buf = StringBuffer('단지,예약건수,예약매출,연장매출,합계,결제건수,결제금액,정산완료\n');
    for (final r in rows) {
      buf.writeln(
        '${r.complexName},${r.reservationCount},${r.grossRevenue},${r.extensionRevenue},${r.totalRevenue},${r.paidOrderCount},${r.paidOrderAmount},${r.isSettled ? 'Y' : 'N'}',
      );
    }
    if (kIsWeb) {
      DanjiSnackBar.show(context, '웹에서는 CSV 저장을 지원하지 않습니다.');
      return;
    }
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final path = '${dir.path}/danjicar_settlement_${_year}_$_month.csv';
      await File(path).writeAsString(buf.toString());
      if (mounted) DanjiSnackBar.show(context, '저장: $path');
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, '저장 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SuperAdminPeriodFilter(
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
        ),
        Expanded(
          child: FutureBuilder<List<SuperAdminRevenueRow>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text(friendlySuperAdminError(snap.error!)));
              }
              final rows = snap.data ?? [];
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('CSV 다운로드'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...rows.map((r) {
                      return SectionCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(r.complexName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                                SuperAdminChip(
                                  label: r.isSettled ? '정산완료' : '미정산',
                                  color: r.isSettled ? const Color(0xFF22C55E) : DanjiColors.danger,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('예약 ${r.reservationCount}건 · ₩${superAdminWon.format(r.totalRevenue)}',
                                style: const TextStyle(fontSize: 13)),
                            Text('결제 ${r.paidOrderCount}건 · ₩${superAdminWon.format(r.paidOrderAmount)}',
                                style: const TextStyle(fontSize: 12, color: DanjiColors.textSecondary)),
                            if (!r.isSettled)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    try {
                                      await widget.service.markSettlement(
                                        complexId: r.complexId,
                                        year: _year,
                                        month: _month,
                                      );
                                      _reload();
                                    } catch (e) {
                                      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                                    }
                                  },
                                  child: const Text('정산 완료 처리'),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
