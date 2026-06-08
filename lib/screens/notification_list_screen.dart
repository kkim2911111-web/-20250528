import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inbox_notification.dart';
import '../services/fcm_navigation_service.dart';
import '../services/notification_inbox_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/danji_snackbar.dart';
import '../widgets/danji_app_bar.dart';

typedef NotificationTapHandler = Future<void> Function(
  BuildContext context,
  InboxNotification item,
);

class NotificationListScreen extends StatefulWidget {
  /// 관리자 RLS 중복 행 방지 — 본인 user_id 알림만 표시
  final bool onlyOwnRows;

  /// null이면 입주민 기본 동작(예약 상세 등)
  final NotificationTapHandler? onNotificationTap;

  const NotificationListScreen({
    super.key,
    this.onlyOwnRows = false,
    this.onNotificationTap,
  });

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final _service = NotificationInboxService();
  final _dateFormat = DateFormat('M.d HH:mm');

  Future<List<InboxNotification>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchNotifications(onlyOwnRows: widget.onlyOwnRows);
    });
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead(onlyOwnRows: widget.onlyOwnRows);
      _reload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, '읽음 처리에 실패했습니다.');
    }
  }

  Future<void> _onTap(InboxNotification item) async {
    if (!item.isRead) {
      try {
        await _service.markRead(item.id);
      } catch (_) {}
    }

    if (widget.onNotificationTap != null) {
      if (!mounted) return;
      await widget.onNotificationTap!(context, item);
      if (!mounted) return;
      _reload();
      return;
    }

    final reservationId = item.reservationId;
    if (reservationId != null && reservationId.isNotEmpty) {
      if (!mounted) return;
      FcmNavigationService.openReservationDetail(reservationId);
      return;
    }

    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '알림',
        extraActions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('모두 읽음'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: DanjiColors.primaryBlue,
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<InboxNotification>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }

            final list = snap.data ?? [];
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.notifications_none_outlined,
                    size: 48,
                    color: DanjiColors.textMuted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '알림이 없습니다',
                    textAlign: TextAlign.center,
                    style: DanjiTypography.bodyRegular.copyWith(
                      color: DanjiColors.textSecondary,
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = list[index];
                return _NotificationTile(
                  item: item,
                  dateFormat: _dateFormat,
                  onTap: () => _onTap(item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final InboxNotification item;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.item,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = item.isRead
        ? DanjiColors.surface
        : DanjiColors.primaryBlue.withValues(alpha: 0.06);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.isRead
                    ? Icons.notifications_none_outlined
                    : Icons.notifications_active_outlined,
                color: item.isRead
                    ? DanjiColors.textMuted
                    : DanjiColors.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: DanjiTypography.subtitle.copyWith(
                        fontWeight:
                            item.isRead ? FontWeight.w600 : FontWeight.w800,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: DanjiTypography.bodyRegular.copyWith(
                          color: DanjiColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (item.createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dateFormat.format(item.createdAt!),
                        style: DanjiTypography.caption.copyWith(
                          color: DanjiColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
