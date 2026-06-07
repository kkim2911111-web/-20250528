import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/notice.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';

class AdminNoticeScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminNoticeScreen({super.key, required this.profile});

  @override
  State<AdminNoticeScreen> createState() => _AdminNoticeScreenState();
}

class _AdminNoticeScreenState extends State<AdminNoticeScreen> {
  final _admin = AdminService();
  final _dateFormat = DateFormat('yyyy.M.d HH:mm');

  Future<List<Notice>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchNotices(widget.profile.complexId);
    });
  }

  Future<void> _openEditor({Notice? notice}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NoticeEditorSheet(
        profile: widget.profile,
        notice: notice,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Notice notice) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공지 삭제'),
        content: Text('"${notice.title}" 공지를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: DanjiTheme.dangerButton,
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _admin.deleteNotice(notice.id);
      if (!mounted) return;
      DanjiSnackBar.show(context, '공지가 삭제되었습니다.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '공지사항'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DanjiColors.buttonBlue,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('공지 등록'),
      ),
      body: FutureBuilder<List<Notice>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(friendlyAdminError(snap.error!)));
          }

          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(
              child: Text(
                '등록된 공지가 없습니다.',
                style: TextStyle(color: DanjiColors.textSecondary),
              ),
            );
          }

          return RefreshIndicator(
            color: DanjiColors.buttonBlue,
            onRefresh: () async => _reload(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notice = list[index];
                return SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notice.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: DanjiColors.textPrimary,
                              ),
                            ),
                          ),
                          _StatusChip(
                            label: notice.isActive ? '노출' : '숨김',
                            color: notice.isActive
                                ? DanjiColors.success
                                : DanjiColors.textMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _StatusChip(
                            label: notice.isGlobal ? '전체 단지' : '우리 단지',
                            color: DanjiColors.buttonBlue,
                          ),
                          if (notice.createdAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _dateFormat.format(notice.createdAt!),
                              style: const TextStyle(
                                color: DanjiColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (notice.content.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          notice.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: DanjiColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _openEditor(notice: notice),
                            child: const Text('수정'),
                          ),
                          TextButton(
                            onPressed: () => _delete(notice),
                            style: TextButton.styleFrom(
                              foregroundColor: DanjiColors.danger,
                            ),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NoticeEditorSheet extends StatefulWidget {
  final StaffProfile profile;
  final Notice? notice;

  const _NoticeEditorSheet({required this.profile, this.notice});

  @override
  State<_NoticeEditorSheet> createState() => _NoticeEditorSheetState();
}

class _NoticeEditorSheetState extends State<_NoticeEditorSheet> {
  final _admin = AdminService();
  final _title = TextEditingController();
  final _content = TextEditingController();

  bool _isGlobal = false;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.notice;
    if (n != null) {
      _title.text = n.title;
      _content.text = n.content;
      _isGlobal = n.isGlobal;
      _isActive = n.isActive;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty) {
      DanjiSnackBar.show(context, '제목을 입력해주세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.notice == null) {
        await _admin.createNotice(
          complexId: widget.profile.complexId,
          title: title,
          content: content,
          isGlobal: _isGlobal,
          isActive: _isActive,
        );
      } else {
        await _admin.updateNotice(
          noticeId: widget.notice!.id,
          complexId: widget.profile.complexId,
          title: title,
          content: content,
          isGlobal: _isGlobal,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.notice == null ? '공지 등록' : '공지 수정',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: DanjiColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '제목',
              border: OutlineInputBorder(),
            ),
            maxLength: 100,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            decoration: const InputDecoration(
              labelText: '내용',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
            maxLength: 2000,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('전체 단지 공지'),
            subtitle: const Text('켜면 모든 단지에 노출됩니다'),
            value: _isGlobal,
            onChanged: (v) => setState(() => _isGlobal = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('노출'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.buttonBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.notice == null ? '등록' : '저장'),
          ),
        ],
      ),
    );
  }
}
