import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
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

  Future<void> _openDetail(SuperAdminRevenueRow r) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: r.complexName,
      child: _SettlementDetailSheet(
        service: widget.service,
        row: r,
        year: _year,
        month: _month,
        onSettled: () {
          Navigator.pop(context);
          _reload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '정산 관리'),
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
                ),
                const SizedBox(height: 4),
                const Text(
                  'completed · 반납 완료일 기준',
                  style: TextStyle(
                    color: DanjiColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SuperAdminRevenueRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SuperAdminLoadingBody();
                }
                if (snap.hasError) {
                  return Center(child: Text(friendlySuperAdminError(snap.error!)));
                }
                final rows = snap.data ?? [];
                return RefreshIndicator(
                  color: DanjiColors.buttonBlue,
                  onRefresh: () async => _reload(),
                  child: rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            SuperAdminEmptyState('정산 데이터가 없습니다.'),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            SectionCard(
                              padding: const EdgeInsets.all(12),
                              child: FilledButton.icon(
                                onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
                                style: superAdminPrimaryFabStyle,
                                icon: const Icon(Icons.download_outlined, size: 18),
                                label: const Text('CSV 다운로드'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...rows.map((r) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SuperAdminListCard(
                                  icon: Icons.payments_outlined,
                                  title: r.complexName,
                                  subtitle: '예약 ${r.reservationCount}건 · '
                                      '₩${superAdminWon.format(r.totalRevenue)}',
                                  trailing: SuperAdminChip(
                                    label: r.isSettled ? '완료' : '미정산',
                                    color: r.isSettled
                                        ? SuperAdminUiColors.availableGreen
                                        : DanjiColors.danger,
                                  ),
                                  onTap: () => _openDetail(r),
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
      ),
    );
  }
}

class _SettlementDetailSheet extends StatefulWidget {
  final SuperAdminService service;
  final SuperAdminRevenueRow row;
  final int year;
  final int month;
  final VoidCallback onSettled;

  const _SettlementDetailSheet({
    required this.service,
    required this.row,
    required this.year,
    required this.month,
    required this.onSettled,
  });

  @override
  State<_SettlementDetailSheet> createState() => _SettlementDetailSheetState();
}

class _SettlementDetailSheetState extends State<_SettlementDetailSheet> {
  late Future<List<SuperAdminSettlementReservation>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = widget.service.fetchSettlementReservations(
      complexId: widget.row.complexId,
      year: widget.year,
      month: widget.month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.55;

    return SizedBox(
      height: sheetHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SuperAdminChip(
            label: r.isSettled ? '정산완료' : '미정산',
            color: r.isSettled
                ? SuperAdminUiColors.availableGreen
                : DanjiColors.danger,
          ),
          const SizedBox(height: 12),
          Text(
            '예약 ${r.reservationCount}건',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('합계 ₩${superAdminWon.format(r.totalRevenue)}'),
          Text(
            '결제 ${r.paidOrderCount}건 · ₩${superAdminWon.format(r.paidOrderAmount)}',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '예약 상세 · ${widget.year}년 ${widget.month}월',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<SuperAdminSettlementReservation>>(
              future: _detailsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      friendlySuperAdminError(snap.error!),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      '해당 월 예약 내역이 없습니다.',
                      style: TextStyle(color: DanjiColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final period =
                        '${item.displayRentalStartAt != null ? superAdminDateTime.format(item.displayRentalStartAt!.toLocal()) : '-'} ~ '
                        '${item.displayRentalEndAt != null ? superAdminDateTime.format(item.displayRentalEndAt!.toLocal()) : '-'}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '#${item.reservationId}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${item.renterName} · $period',
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Text(
                        '₩${superAdminWon.format(item.totalPrice)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: DanjiColors.buttonBlue,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (!r.isSettled) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.service.markSettlement(
                    complexId: r.complexId,
                    year: widget.year,
                    month: widget.month,
                  );
                  widget.onSettled();
                } catch (e) {
                  if (mounted) {
                    DanjiSnackBar.show(context, friendlySuperAdminError(e));
                  }
                }
              },
              style: superAdminPrimaryFabStyle,
              child: const Text('정산 완료 처리'),
            ),
          ],
        ],
      ),
    );
  }
}
