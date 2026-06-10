import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notice.dart';
import '../services/notice_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

/// 공지사항 전체 목록
class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  final _service = NoticeService();
  final _dateFormat = DateFormat('yyyy.MM.dd');
  Future<List<Notice>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchActiveNotices(limit: 50);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '공지사항'),
      body: FutureBuilder<List<Notice>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final notices = snap.data ?? [];
          if (notices.isEmpty) {
            return const Center(
              child: Text(
                '등록된 공지가 없습니다.',
                style: TextStyle(color: DanjiColors.textSecondary),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: notices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _NoticeListTile(
                notice: notices[index],
                dateLabel: notices[index].createdAt != null
                    ? _dateFormat.format(notices[index].createdAt!)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _NoticeListTile extends StatefulWidget {
  final Notice notice;
  final String? dateLabel;

  const _NoticeListTile({required this.notice, this.dateLabel});

  @override
  State<_NoticeListTile> createState() => _NoticeListTileState();
}

class _NoticeListTileState extends State<_NoticeListTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice.isGlobal)
                    Container(
                      margin: const EdgeInsets.only(right: 6, top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DanjiColors.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '전체',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DanjiColors.primaryBlue,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: DanjiColors.textPrimary,
                          ),
                        ),
                        if (widget.dateLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.dateLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DanjiColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                    color: DanjiColors.textMuted,
                  ),
                ],
              ),
              if (_expanded && notice.content.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  notice.content,
                  style: DanjiTypography.bodyRegular.copyWith(
                    color: DanjiColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
