import 'package:flutter/material.dart';

import '../services/notification_inbox_service.dart';
import '../theme/danji_colors.dart';

/// 홈·관리자 대시보드 공통 알림 벨 + 미읽음 배지
class NotificationBellButton extends StatefulWidget {
  final VoidCallback onPressed;

  /// true면 본인 user_id 행만 집계 (관리자 RLS 중복 방지)
  final bool onlyOwnRows;

  const NotificationBellButton({
    super.key,
    required this.onPressed,
    this.onlyOwnRows = false,
  });

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _service = NotificationInboxService();
  Future<int>? _unreadFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _unreadFuture = _service.fetchUnreadCount(onlyOwnRows: widget.onlyOwnRows);
    });
  }

  @override
  void didUpdateWidget(covariant NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onlyOwnRows != widget.onlyOwnRows) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _unreadFuture,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return IconButton(
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: const Icon(Icons.notifications_outlined, size: 22),
          ),
          color: DanjiColors.textPrimary,
          tooltip: '알림',
          onPressed: () {
            widget.onPressed();
            _reload();
          },
        );
      },
    );
  }
}
