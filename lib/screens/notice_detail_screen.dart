import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notice.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

/// 공지사항 상세
class NoticeDetailScreen extends StatelessWidget {
  final Notice notice;

  const NoticeDetailScreen({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final dateLabel = notice.createdAt != null
        ? DateFormat('yyyy.MM.dd').format(notice.createdAt!)
        : null;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '공지사항'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (notice.isGlobal)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DanjiColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '전체 공지',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DanjiColors.primaryBlue,
                ),
              ),
            ),
          Text(
            notice.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: DanjiColors.textPrimary,
              height: 1.35,
            ),
          ),
          if (dateLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              dateLabel,
              style: const TextStyle(
                fontSize: 13,
                color: DanjiColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            notice.content.isNotEmpty
                ? notice.content
                : '내용이 없습니다.',
            style: DanjiTypography.bodyRegular.copyWith(
              color: DanjiColors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
