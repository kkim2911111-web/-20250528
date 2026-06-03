import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/point_history_entry.dart';
import '../services/point_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

class PointScreen extends StatefulWidget {
  const PointScreen({super.key});

  @override
  State<PointScreen> createState() => _PointScreenState();
}

class _PointScreenState extends State<PointScreen> {
  final _service = PointService();
  final _dateFormat = DateFormat('yyyy.MM.dd HH:mm');

  Future<({int balance, List<PointHistoryEntry> history})>? _future;

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
      body: FutureBuilder<({int balance, List<PointHistoryEntry> history})>(
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
                    sliver: SliverList.separated(
                      itemCount: data.history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _HistoryTile(
                          entry: data.history[index],
                          dateFormat: _dateFormat,
                          formatPoints: _formatPoints,
                        );
                      },
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
  final DateFormat dateFormat;
  final String Function(int) formatPoints;

  const _HistoryTile({
    required this.entry,
    required this.dateFormat,
    required this.formatPoints,
  });

  @override
  Widget build(BuildContext context) {
    final earned = entry.isEarned;
    final amountText =
        '${earned ? '+' : ''}${formatPoints(entry.amount.abs())}P';

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
              color: (earned ? DanjiColors.brandBlue : DanjiColors.toneRed)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              earned ? Icons.add_rounded : Icons.remove_rounded,
              color: earned ? DanjiColors.brandBlue : DanjiColors.toneRed,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.typeLabel,
                  style: DanjiTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    dateFormat.format(entry.createdAt!),
                    style: DanjiTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          Text(
            amountText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: earned ? DanjiColors.brandBlue : DanjiColors.toneRed,
            ),
          ),
        ],
      ),
    );
  }
}
