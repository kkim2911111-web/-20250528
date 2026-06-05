import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/point_history_entry.dart';
import '../models/point_reservation_summary.dart';
import '../services/point_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/month_filter_bar.dart';

abstract final class _PointUiColors {
  static const badgeEarnBg = Color(0xFFE8F0FE);
  static const badgeEarnFg = DanjiColors.brandBlue;
  static const badgeUseBg = Color(0xFFF2F4F6);
  static const badgeUseFg = Color(0xFF6B7684);
  static const badgeRestoreBg = Color(0xFFE8F8EF);
  static const badgeRestoreFg = DanjiColors.success;
  static const badgeExpireBg = Color(0xFFF2F4F6);
  static const badgeExpireFg = Color(0xFF6B7684);
}

class PointScreen extends StatefulWidget {
  const PointScreen({super.key});

  @override
  State<PointScreen> createState() => _PointScreenState();
}

class _PointScreenState extends State<PointScreen> {
  final _service = PointService();
  final _dateFormat = DateFormat('yyyy.MM.dd HH:mm');
  final _monthHeaderFormat = DateFormat('yyyy년 M월');
  late DateTime _selectedMonth;

  Future<
      ({
        int balance,
        List<PointHistoryEntry> history,
        Map<String, PointReservationSummary> reservationMeta,
      })>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _reload();
  }

  bool get _canGoNextMonth {
    final now = DateTime.now();
    return _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year &&
            _selectedMonth.month < now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  List<PointHistoryEntry> _filterByMonth(List<PointHistoryEntry> history) {
    return history.where((entry) {
      final dt = entry.createdAt;
      if (dt == null) return false;
      return dt.year == _selectedMonth.year &&
          dt.month == _selectedMonth.month;
    }).toList();
  }

  ({int earned, int used}) _monthTotals(List<PointHistoryEntry> history) {
    var earned = 0;
    var used = 0;
    for (final entry in history) {
      if (entry.isCancelled) continue;
      if (entry.isSpendEntry ||
          entry.isUseType ||
          entry.isExpireType ||
          entry.amount < 0) {
        used += entry.amount.abs();
      } else if (entry.amount > 0) {
        earned += entry.amount;
      }
    }
    return (earned: earned, used: used);
  }

  void _reload() {
    setState(() {
      _future = _service.fetchPointSummary();
    });
  }

  String _formatPoints(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '보유 포인트',
        showHome: false,
        extraActions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<
          ({
            int balance,
            List<PointHistoryEntry> history,
            Map<String, PointReservationSummary> reservationMeta,
          })>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DanjiColors.accentRed),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snap.data!;
          final monthHistory = _filterByMonth(data.history);
          final monthTotals = _monthTotals(monthHistory);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: _BalanceHeader(points: data.balance),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: MonthFilterBar(
                      label: _monthHeaderFormat.format(_selectedMonth),
                      canGoNext: _canGoNextMonth,
                      onPrevious: () => _shiftMonth(-1),
                      onNext: _canGoNextMonth ? () => _shiftMonth(1) : null,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      '적립 +${_formatPoints(monthTotals.earned)}P / 사용 -${_formatPoints(monthTotals.used)}P',
                      style: DanjiTypography.body.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DanjiColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      '적립 · 사용 내역',
                      style: DanjiTypography.subtitle.copyWith(
                        fontSize: 18,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (monthHistory.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        data.history.isEmpty
                            ? '포인트 내역이 없습니다.'
                            : '${_monthHeaderFormat.format(_selectedMonth)} 내역이 없습니다.',
                        style: DanjiTypography.secondary,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index < monthHistory.length - 1 ? 10 : 0,
                          ),
                          child: _HistoryTile(
                            entry: monthHistory[index],
                            reservationMeta: data.reservationMeta,
                            dateFormat: _dateFormat,
                            formatPoints: _formatPoints,
                          ),
                        ),
                        childCount: monthHistory.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  final int points;

  const _BalanceHeader({required this.points});

  String _format(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DanjiColors.brandBlue.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '현재 보유 포인트',
            style: DanjiTypography.secondary.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${_format(points)}P',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: DanjiColors.brandBlue,
                letterSpacing: -0.5,
                height: 1.0,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final PointHistoryEntry entry;
  final Map<String, PointReservationSummary> reservationMeta;
  final DateFormat dateFormat;
  final String Function(int) formatPoints;

  const _HistoryTile({
    required this.entry,
    required this.reservationMeta,
    required this.dateFormat,
    required this.formatPoints,
  });

  Color _amountColor(PointHistoryBadgeKind kind, bool cancelled) {
    if (cancelled) {
      return DanjiColors.textSecondary.withValues(alpha: 0.55);
    }
    switch (kind) {
      case PointHistoryBadgeKind.earn:
        return _PointUiColors.badgeEarnFg;
      case PointHistoryBadgeKind.use:
      case PointHistoryBadgeKind.expire:
        return _PointUiColors.badgeUseFg;
      case PointHistoryBadgeKind.restore:
        return _PointUiColors.badgeRestoreFg;
      case PointHistoryBadgeKind.cancelled:
      case PointHistoryBadgeKind.none:
        return DanjiColors.textSecondary;
    }
  }

  Widget _badgeChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget? _typeBadge(PointHistoryBadgeKind kind) {
    switch (kind) {
      case PointHistoryBadgeKind.earn:
        return _badgeChip(
          '적립',
          _PointUiColors.badgeEarnBg,
          _PointUiColors.badgeEarnFg,
        );
      case PointHistoryBadgeKind.use:
        return _badgeChip(
          '사용',
          _PointUiColors.badgeUseBg,
          _PointUiColors.badgeUseFg,
        );
      case PointHistoryBadgeKind.restore:
        return _badgeChip(
          '복구',
          _PointUiColors.badgeRestoreBg,
          _PointUiColors.badgeRestoreFg,
        );
      case PointHistoryBadgeKind.expire:
        return _badgeChip(
          '만료',
          _PointUiColors.badgeExpireBg,
          _PointUiColors.badgeExpireFg,
        );
      case PointHistoryBadgeKind.cancelled:
        return _badgeChip(
          '취소',
          _PointUiColors.badgeUseBg,
          _PointUiColors.badgeUseFg,
        );
      case PointHistoryBadgeKind.none:
        return null;
    }
  }

  String _amountText(
    bool cancelled,
    bool isSpend,
    bool isRestore,
    bool earned,
  ) {
    final value = formatPoints(entry.amount.abs());
    if (cancelled) {
      final sign = entry.amount < 0 ? '-' : '+';
      return '$sign${value}P';
    }
    if (isRestore || (earned && entry.amount > 0)) return '+${value}P';
    if (isSpend || entry.isUseType || entry.isExpireType || entry.amount < 0) {
      return '-${value}P';
    }
    if (entry.amount > 0) return '+${value}P';
    return '${value}P';
  }


  @override
  Widget build(BuildContext context) {
    final cancelled = entry.isCancelled;
    final isRestore = entry.isRestoreType;
    final isSpend = entry.isSpendEntry;
    final isEarn =
        entry.isEarned && !isSpend && !isRestore && !entry.isExpireType;
    final badgeKind = entry.badgeKind;
    final vehicleName = entry.displayVehicleName(reservationMeta);
    final amountText = _amountText(cancelled, isSpend, isRestore, isEarn);
    final badge = _typeBadge(badgeKind);
    final muted = DanjiColors.textSecondary.withValues(alpha: 0.55);
    final labelStyle = DanjiTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: cancelled ? muted : DanjiColors.textPrimary,
      decoration: cancelled ? TextDecoration.lineThrough : null,
      decorationColor: muted,
    );
    final amountStyle = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: _amountColor(badgeKind, cancelled),
      decoration: cancelled ? TextDecoration.lineThrough : null,
      decorationColor: muted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (badge != null) ...[
                      badge,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        vehicleName,
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (entry.createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    dateFormat.format(entry.createdAt!),
                    style: DanjiTypography.caption.copyWith(
                      fontSize: 13,
                      color: cancelled ? muted : DanjiColors.textSecondary,
                      decoration:
                          cancelled ? TextDecoration.lineThrough : null,
                      decorationColor: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(amountText, style: amountStyle),
        ],
      ),
    );
  }
}
