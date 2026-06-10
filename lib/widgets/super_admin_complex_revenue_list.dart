import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_detail.dart';
import '../models/super_admin_models.dart';
import '../screens/super_admin/super_admin_common.dart';
import '../services/super_admin_service.dart';
import '../theme/danji_colors.dart';
import '../utils/platform_fee_billing.dart';
import '../utils/rental_detail_navigation.dart';

/// 단지별 매출·수수료 — 접이식 목록 (매출 큰 순, ₩0 하단·흐림)
List<SuperAdminRevenueRow> sortComplexRevenueRows(
  List<SuperAdminRevenueRow> rows,
) {
  final nonZero = rows.where((r) => r.totalRevenue > 0).toList()
    ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
  final zero = rows.where((r) => r.totalRevenue == 0).toList()
    ..sort((a, b) => a.complexName.compareTo(b.complexName));
  return [...nonZero, ...zero];
}

class SuperAdminComplexRevenueList extends StatefulWidget {
  final List<SuperAdminRevenueRow> rows;
  final bool isFeeEstimate;
  final VoidCallback? onOpenRevenue;
  final SuperAdminService? service;
  final int year;
  final int month;

  const SuperAdminComplexRevenueList({
    super.key,
    required this.rows,
    this.isFeeEstimate = false,
    this.onOpenRevenue,
    this.service,
    this.year = 0,
    this.month = 0,
  });

  @override
  State<SuperAdminComplexRevenueList> createState() =>
      _SuperAdminComplexRevenueListState();
}

class _SuperAdminComplexRevenueListState
    extends State<SuperAdminComplexRevenueList> {
  static const _maxVisible = 5;
  static const _showAllThreshold = 10;

  final Set<String> _expandedIds = {};

  @override
  Widget build(BuildContext context) {
    final sorted = sortComplexRevenueRows(widget.rows);
    if (sorted.isEmpty) {
      return const Center(
        child: Text(
          '해당 월 매출·등록 차량이 없습니다.',
          style: TextStyle(color: DanjiColors.textSecondary),
        ),
      );
    }

    final showAllLink = sorted.length > _showAllThreshold;
    final visible = showAllLink ? sorted.take(_maxVisible).toList() : sorted;

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: visible.length + (showAllLink ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (showAllLink && index == visible.length) {
          return TextButton(
            onPressed: widget.onOpenRevenue,
            child: const Text('전체 보기'),
          );
        }
        final row = visible[index];
        return _ComplexRevenueCollapsibleTile(
          key: ValueKey(row.complexId),
          row: row,
          isZeroRevenue: row.totalRevenue == 0,
          isFeeEstimate: widget.isFeeEstimate,
          service: widget.service,
          year: widget.year,
          month: widget.month,
          expanded: _expandedIds.contains(row.complexId),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedIds.add(row.complexId);
              } else {
                _expandedIds.remove(row.complexId);
              }
            });
          },
        );
      },
    );
  }
}

class _ComplexRevenueCollapsibleTile extends StatefulWidget {
  final SuperAdminRevenueRow row;
  final bool isZeroRevenue;
  final bool isFeeEstimate;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final SuperAdminService? service;
  final int year;
  final int month;

  const _ComplexRevenueCollapsibleTile({
    super.key,
    required this.row,
    required this.isZeroRevenue,
    required this.isFeeEstimate,
    required this.expanded,
    required this.onExpansionChanged,
    this.service,
    this.year = 0,
    this.month = 0,
  });

  @override
  State<_ComplexRevenueCollapsibleTile> createState() =>
      _ComplexRevenueCollapsibleTileState();
}

class _ComplexRevenueCollapsibleTileState
    extends State<_ComplexRevenueCollapsibleTile>
    with SingleTickerProviderStateMixin {
  final _headerKey = GlobalKey();

  void _toggle() {
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    final offsetBefore = position?.pixels;

    RenderBox? headerBox;
    double? headerTopBefore;
    final headerContext = _headerKey.currentContext;
    if (headerContext != null) {
      headerBox = headerContext.findRenderObject() as RenderBox?;
      headerTopBefore = headerBox?.localToGlobal(Offset.zero).dy;
    }

    final next = !widget.expanded;
    widget.onExpansionChanged(next);

    if (position != null && headerTopBefore != null && next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _headerKey.currentContext;
        if (ctx == null) return;
        final box = ctx.findRenderObject() as RenderBox?;
        final headerTopAfter = box?.localToGlobal(Offset.zero).dy;
        if (headerTopAfter == null || offsetBefore == null) return;
        final delta = headerTopAfter - headerTopBefore!;
        if (delta.abs() > 0.5) {
          position.jumpTo(offsetBefore + delta);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final vehicles = r.billableVehicleCount;
    final fee = platformFeeAmount(vehicles);
    final muted = widget.isZeroRevenue;

    final summaryStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: muted ? DanjiColors.textMuted : DanjiColors.textPrimary,
      height: 1.35,
    );

    return Material(
      color: DanjiColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DanjiColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: _headerKey,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${r.complexName} — 매출 ₩${superAdminWon.format(r.totalRevenue)} · '
                        '수수료 ₩${superAdminWon.format(fee)}',
                        style: summaryStyle,
                      ),
                    ),
                    Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: DanjiColors.textMuted,
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '예약 ${r.reservationCount}건 · ${r.settlementBadgeLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted
                              ? DanjiColors.textMuted
                              : DanjiColors.textSecondary,
                        ),
                      ),
                      if (r.extensionRevenue > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '연장 매출 ₩${superAdminWon.format(r.extensionRevenue)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted
                                ? DanjiColors.textMuted
                                : DanjiColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '수수료 ${vehicles}대 × 10만원'
                        '${widget.isFeeEstimate ? ' (예상)' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: muted
                              ? DanjiColors.textMuted
                              : DanjiColors.textSecondary,
                        ),
                      ),
                      if (widget.expanded &&
                          widget.service != null &&
                          widget.year > 0 &&
                          widget.month > 0) ...[
                        const SizedBox(height: 10),
                        _ComplexSettlementRentalList(
                          future: widget.service!.fetchSettlementSheet(
                            complexId: r.complexId,
                            year: widget.year,
                            month: widget.month,
                          ),
                          service: widget.service!,
                          complexName: r.complexName,
                        ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: widget.expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComplexSettlementRentalList extends StatelessWidget {
  final Future<SuperAdminSettlementSheet> future;
  final SuperAdminService service;
  final String complexName;

  const _ComplexSettlementRentalList({
    required this.future,
    required this.service,
    required this.complexName,
  });

  static final _won = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SuperAdminSettlementSheet>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Text(
            '대여 목록을 불러오지 못했습니다.',
            style: TextStyle(fontSize: 12, color: DanjiColors.textMuted),
          );
        }

        final items = snap.data?.items ?? const [];
        if (items.isEmpty) {
          return const Text(
            '해당 월 완료 대여 내역이 없습니다.',
            style: TextStyle(fontSize: 12, color: DanjiColors.textMuted),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '대여 내역',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DanjiColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 12),
              _SettlementRentalRow(
                item: items[i],
                onTap: () => openSuperAdminRentalDetail(
                  context,
                  reservationId: items[i].reservationId,
                  service: service,
                  prefetch: RentalDetailPrefetch(complexName: complexName),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SettlementRentalRow extends StatelessWidget {
  final SuperAdminSettlementReservation item;
  final VoidCallback onTap;

  const _SettlementRentalRow({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.reservationNumberLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DanjiColors.buttonBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.renterName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DanjiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '₩${_ComplexSettlementRentalList._won.format(item.totalPrice)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DanjiColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: DanjiColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
