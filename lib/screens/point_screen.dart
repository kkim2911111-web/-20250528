import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/point_history_entry.dart';
import '../models/point_reservation_summary.dart';
import '../services/point_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

abstract final class _PointUiColors {
  static const expiryGray = Color(0xFF8B95A1);
  static const expiryOrange = Color(0xFFFF9800);
  static const badgeUseBg = Color(0xFFFFEBEE);
  static const badgeRestoreBg = Color(0xFFE8F8EF);
  static const badgeExpireBg = Color(0xFFF2F4F6);
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

  Future<
      ({
        int balance,
        List<PointHistoryEntry> history,
        Map<String, PointReservationSummary> reservationMeta,
      })>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
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

  int _historyListChildCount(
    List<({String monthKey, String monthLabel, List<PointHistoryEntry> items})>
        groups,
  ) {
    var count = groups.length;
    for (final g in groups) {
      count += g.items.length;
    }
    return count;
  }

  Widget _historyListChild(
    List<({String monthKey, String monthLabel, List<PointHistoryEntry> items})>
        groups,
    Map<String, PointReservationSummary> reservationMeta,
    int index,
  ) {
    var offset = 0;
    for (final group in groups) {
      if (index == offset) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            group.monthLabel,
            style: DanjiTypography.subtitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: DanjiColors.textPrimary,
            ),
          ),
        );
      }
      offset++;
      for (var i = 0; i < group.items.length; i++) {
        if (index == offset) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: i < group.items.length - 1 ? 10 : 16,
            ),
            child: _HistoryTile(
              entry: group.items[i],
              reservationMeta: reservationMeta,
              dateFormat: _dateFormat,
              formatPoints: _formatPoints,
            ),
          );
        }
        offset++;
      }
    }
    return const SizedBox.shrink();
  }

  List<({String monthKey, String monthLabel, List<PointHistoryEntry> items})>
      _groupByMonth(List<PointHistoryEntry> history) {
    final buckets = <String, List<PointHistoryEntry>>{};
    for (final entry in history) {
      final dt = entry.createdAt ?? DateTime.now();
      final key = DateFormat('yyyy-MM').format(dt);
      buckets.putIfAbsent(key, () => []).add(entry);
    }
    final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys)
        (
          monthKey: key,
          monthLabel: _monthHeaderFormat.format(DateTime.parse('$key-01')),
          items: buckets[key]!,
        ),
    ];
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
          final monthGroups = _groupByMonth(data.history);
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
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      '적립 · 사용 내역',
                      style: DanjiTypography.subtitle.copyWith(
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (data.history.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '포인트 내역이 없습니다.',
                        style: DanjiTypography.secondary,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _historyListChild(
                          monthGroups,
                          data.reservationMeta,
                          index,
                        ),
                        childCount: _historyListChildCount(monthGroups),
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
            style: DanjiTypography.secondary.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            '${_format(points)}P',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: DanjiColors.brandBlue,
              letterSpacing: -1,
              height: 1.1,
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

  Color _expiryColor(PointExpiryTone tone) {
    switch (tone) {
      case PointExpiryTone.urgentRed:
        return DanjiColors.toneRed;
      case PointExpiryTone.urgentOrange:
        return _PointUiColors.expiryOrange;
      case PointExpiryTone.normal:
        return _PointUiColors.expiryGray;
      case PointExpiryTone.muted:
        return DanjiColors.textSecondary.withValues(alpha: 0.55);
    }
  }

  Color _accentColor({
    required bool cancelled,
    required bool isExpire,
    required bool isRestore,
    required bool isUse,
    required bool isEarn,
  }) {
    if (cancelled || isExpire) {
      return DanjiColors.textSecondary.withValues(alpha: 0.55);
    }
    if (isRestore) return DanjiColors.success;
    if (isUse) return DanjiColors.toneRed;
    if (isEarn) return DanjiColors.brandBlue;
    return entry.isEarned ? DanjiColors.brandBlue : DanjiColors.toneRed;
  }

  IconData _icon({
    required bool cancelled,
    required bool isExpire,
    required bool isRestore,
    required bool isUse,
    required bool isEarn,
  }) {
    if (cancelled || isExpire) return Icons.schedule_rounded;
    if (isRestore) return Icons.replay_rounded;
    if (isUse) return Icons.remove_rounded;
    if (isEarn) return Icons.add_rounded;
    return entry.isEarned ? Icons.add_rounded : Icons.remove_rounded;
  }

  Widget? _typeBadge({
    required bool cancelled,
    required bool isExpire,
    required bool isRestore,
    required bool isUse,
  }) {
    if (cancelled) return null;
    String? label;
    Color bg;
    Color fg;
    if (isUse) {
      label = '사용';
      bg = _PointUiColors.badgeUseBg;
      fg = DanjiColors.toneRed;
    } else if (isRestore) {
      label = '복구';
      bg = _PointUiColors.badgeRestoreBg;
      fg = DanjiColors.success;
    } else if (isExpire) {
      label = '만료';
      bg = _PointUiColors.badgeExpireBg;
      fg = DanjiColors.textSecondary;
    } else {
      return null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
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
    final isExpire = entry.isExpireType;
    final isRestore = entry.isRestoreType;
    final isUse = entry.isUseType;
    final isSpend = entry.isSpendEntry;
    final isEarn =
        entry.isEarned && !isSpend && !isRestore && !isExpire;
    final accent = _accentColor(
      cancelled: cancelled,
      isExpire: isExpire,
      isRestore: isRestore,
      isUse: isUse,
      isEarn: isEarn,
    );
    final title = entry.displayLabel(reservationMeta);
    final amountText = _amountText(cancelled, isSpend, isRestore, isEarn);
    final expiry = PointExpiryDisplay.forEntry(entry);
    final badge = _typeBadge(
      cancelled: cancelled,
      isExpire: isExpire,
      isRestore: isRestore,
      isUse: isUse,
    );
    final muted = DanjiColors.textSecondary.withValues(alpha: 0.55);
    final labelStyle = DanjiTypography.body.copyWith(
      fontWeight: FontWeight.w600,
      color: cancelled ? muted : DanjiColors.textPrimary,
      decoration: cancelled ? TextDecoration.lineThrough : null,
      decorationColor: muted,
    );
    final amountStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: cancelled ? muted : accent,
      decoration: cancelled ? TextDecoration.lineThrough : null,
      decorationColor: muted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (cancelled ? DanjiColors.textMuted : accent)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _icon(
                cancelled: cancelled,
                isExpire: isExpire,
                isRestore: isRestore,
                isUse: isUse,
                isEarn: isEarn,
              ),
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: labelStyle,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge,
                    ],
                    if (cancelled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '취소됨',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (entry.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    dateFormat.format(entry.createdAt!),
                    style: DanjiTypography.caption.copyWith(
                      color: cancelled ? muted : DanjiColors.textSecondary,
                      decoration:
                          cancelled ? TextDecoration.lineThrough : null,
                      decorationColor: muted,
                    ),
                  ),
                ],
                if (expiry != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    expiry.text,
                    style: DanjiTypography.caption.copyWith(
                      color: cancelled
                          ? muted
                          : _expiryColor(expiry.tone),
                      fontWeight: expiry.tone == PointExpiryTone.urgentRed ||
                              expiry.tone == PointExpiryTone.urgentOrange
                          ? FontWeight.w700
                          : FontWeight.w500,
                      decoration:
                          cancelled ? TextDecoration.lineThrough : null,
                      decorationColor: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(amountText, style: amountStyle),
        ],
      ),
    );
  }
}
