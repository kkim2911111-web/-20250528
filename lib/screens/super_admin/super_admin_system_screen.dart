import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/section_card.dart';

class SuperAdminSystemScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminSystemScreen({super.key, required this.service});
  @override
  State<SuperAdminSystemScreen> createState() => _SuperAdminSystemScreenState();
}

class _SuperAdminSystemScreenState extends State<SuperAdminSystemScreen> {
  bool _maintenance = false;
  final _maintenanceMsg = TextEditingController();
  final _pushTitle = TextEditingController();
  final _pushBody = TextEditingController();
  Future<List<SuperAdminBanner>>? _bannersFuture;
  bool _loading = true;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maintenanceMsg.dispose();
    _pushTitle.dispose();
    _pushBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await widget.service.fetchSettings();
      final maintenance = settings['maintenance'];
      if (maintenance is Map) {
        _maintenance = maintenance['enabled'] == true;
        _maintenanceMsg.text = maintenance['message']?.toString() ?? '';
      }
      _bannersFuture = widget.service.fetchBanners();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveMaintenance() async {
    try {
      await widget.service.setMaintenance(
        enabled: _maintenance,
        message: _maintenanceMsg.text,
      );
      if (mounted) DanjiSnackBar.show(context, '점검모드 설정이 저장되었습니다.');
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _editBanner([SuperAdminBanner? b]) async {
    final sub = TextEditingController(text: b?.subTitle ?? '');
    final main = TextEditingController(text: b?.mainTitle ?? '');
    final desc = TextEditingController(text: b?.description ?? '');
    var active = b?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(b == null ? '배너 등록' : '배너 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: sub, decoration: const InputDecoration(labelText: '상단 텍스트')),
              TextField(controller: main, decoration: const InputDecoration(labelText: '메인 텍스트')),
              TextField(controller: desc, decoration: const InputDecoration(labelText: '설명')),
              SwitchListTile(title: const Text('노출'), value: active, onChanged: (v) => setLocal(() => active = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.upsertBanner(
        id: b?.id,
        subTitle: sub.text,
        mainTitle: main.text,
        description: desc.text,
        isActive: active,
      );
      _load();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _editNotice() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 공지 등록'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
            TextField(controller: content, maxLines: 4, decoration: const InputDecoration(labelText: '내용')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('등록')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.upsertNotice(
        title: title.text,
        content: content.text,
      );
      if (mounted) DanjiSnackBar.show(context, '공지가 등록되었습니다.');
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _broadcast() async {
    if (_pushTitle.text.trim().isEmpty || _pushBody.text.trim().isEmpty) return;
    setState(() => _pushing = true);
    try {
      final n = await widget.service.broadcastPush(
        title: _pushTitle.text.trim(),
        body: _pushBody.text.trim(),
      );
      if (mounted) DanjiSnackBar.show(context, '푸시 발송 시도: $n건');
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('점검모드', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('점검모드 활성화'),
                value: _maintenance,
                onChanged: (v) => setState(() => _maintenance = v),
              ),
              TextField(
                controller: _maintenanceMsg,
                decoration: const InputDecoration(labelText: '점검 안내 메시지', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _saveMaintenance, child: const Text('저장')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('배너 관리', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  TextButton(onPressed: () => _editBanner(), child: const Text('추가')),
                ],
              ),
              FutureBuilder<List<SuperAdminBanner>>(
                future: _bannersFuture,
                builder: (context, snap) {
                  final list = snap.data ?? [];
                  if (list.isEmpty) return const Text('배너 없음', style: TextStyle(color: DanjiColors.textSecondary));
                  return Column(
                    children: list.map((b) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(b.mainTitle),
                      subtitle: Text(b.subTitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editBanner(b)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: DanjiColors.danger),
                            onPressed: () async {
                              await widget.service.deleteBanner(b.id);
                              _load();
                            },
                          ),
                        ],
                      ),
                    )).toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('공지사항', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _editNotice, child: const Text('전체 공지 등록')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('전체 푸시', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(controller: _pushTitle, decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _pushBody, decoration: const InputDecoration(labelText: '내용', border: OutlineInputBorder()), maxLines: 2),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _pushing ? null : _broadcast,
                child: _pushing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('발송 (최대 200명)'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
