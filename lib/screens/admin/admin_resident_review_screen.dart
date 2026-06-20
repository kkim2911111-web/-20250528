import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/resident_review_item.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/section_card.dart';

/// 단지 관리자 — 입주민 인증 심사 (심사 대기 목록)
enum AdminResidentApprovalFilter { pending, approved, all }

extension on AdminResidentApprovalFilter {
  String get label {
    switch (this) {
      case AdminResidentApprovalFilter.all:
        return '전체';
      case AdminResidentApprovalFilter.approved:
        return '승인';
      case AdminResidentApprovalFilter.pending:
        return '대기';
    }
  }
}

class AdminResidentReviewScreen extends StatefulWidget {
  final AdminService admin;
  final Future<List<ResidentReviewItem>>? future;
  final VoidCallback onReload;

  const AdminResidentReviewScreen({
    super.key,
    required this.admin,
    required this.future,
    required this.onReload,
  });

  @override
  State<AdminResidentReviewScreen> createState() =>
      _AdminResidentReviewScreenState();
}

class _AdminResidentReviewScreenState extends State<AdminResidentReviewScreen> {
  AdminResidentApprovalFilter _filter = AdminResidentApprovalFilter.pending;
  final _dateTime = DateFormat('yyyy.MM.dd HH:mm');

  Future<void> _approve(ResidentReviewItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('입주민 승인'),
        content: Text(
          '${item.fullName} (${item.dongHoLabel}) 님의 입주민 인증을 승인할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('승인'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.admin.reviewResident(userId: item.userId, approved: true);
      if (!mounted) return;
      DanjiSnackBar.show(context, '${item.fullName} 입주민 승인 완료');
      widget.onReload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<void> _reject(ResidentReviewItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('입주민 거절'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '거절 사유',
              hintText: '예: 동·호수 확인이 필요합니다',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('거절'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;

    try {
      await widget.admin.reviewResident(
        userId: item.userId,
        approved: false,
        rejectionReason: reason.isEmpty ? '입주민 인증 정보 확인 불가' : reason,
      );
      if (!mounted) return;
      DanjiSnackBar.show(context, '입주민 인증 거절 처리되었습니다');
      widget.onReload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  List<ResidentReviewItem> _applyFilter(List<ResidentReviewItem> pending) {
    switch (_filter) {
      case AdminResidentApprovalFilter.pending:
      case AdminResidentApprovalFilter.all:
        return pending;
      case AdminResidentApprovalFilter.approved:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ResidentReviewItem>>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(friendlyAdminError(snap.error!)),
              ),
            ],
          );
        }

        final pending = snap.data ?? [];
        final filtered = _applyFilter(pending);

        if (_filter == AdminResidentApprovalFilter.approved) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _FilterBar(
                filter: _filter,
                pendingCount: pending.length,
                onFilterChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 40),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '승인된 입주민은 「입주민」 탭에서\n이용 이력과 함께 확인할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DanjiColors.textSecondary),
                ),
              ),
            ],
          );
        }

        if (filtered.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _FilterBar(
                filter: _filter,
                pendingCount: pending.length,
                onFilterChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 80),
              const Center(
                child: Text(
                  '심사 대기 중인 입주민이 없습니다.',
                  style: TextStyle(color: DanjiColors.textSecondary),
                ),
              ),
            ],
          );
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: filtered.length + 1,
          separatorBuilder: (context, index) {
            if (index == 0) return const SizedBox.shrink();
            return const SizedBox(height: 10);
          },
          itemBuilder: (context, index) {
            if (index == 0) {
              return _FilterBar(
                filter: _filter,
                pendingCount: pending.length,
                onFilterChanged: (v) => setState(() => _filter = v),
              );
            }
            final item = filtered[index - 1];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ResidentReviewCard(
                item: item,
                requestedLabel: item.requestedAt != null
                    ? _dateTime.format(item.requestedAt!)
                    : null,
                onApprove: () => _approve(item),
                onReject: () => _reject(item),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  final AdminResidentApprovalFilter filter;
  final int pendingCount;
  final ValueChanged<AdminResidentApprovalFilter> onFilterChanged;

  const _FilterBar({
    required this.filter,
    required this.pendingCount,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AdminResidentApprovalFilter>(
                isExpanded: true,
                value: filter,
                items: AdminResidentApprovalFilter.values
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  onFilterChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '심사 대기 $pendingCount건',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidentReviewCard extends StatelessWidget {
  final ResidentReviewItem item;
  final String? requestedLabel;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ResidentReviewCard({
    required this.item,
    required this.requestedLabel,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: DanjiColors.buttonBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '심사 대기',
                  style: TextStyle(
                    color: DanjiColors.buttonBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.dongHoLabel,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (requestedLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              '신청: $requestedLabel',
              style: const TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DanjiColors.accentRed,
                    side: BorderSide(
                      color: DanjiColors.accentRed.withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: DanjiColors.buttonBlue,
                  ),
                  child: const Text('승인'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
