import 'package:flutter/material.dart';

import '../../models/app_feature_config.dart';
import '../../models/super_admin_models.dart';
import '../../utils/feature_kill_switch.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminSystemScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminSystemScreen({super.key, required this.service});
  @override
  State<SuperAdminSystemScreen> createState() => _SuperAdminSystemScreenState();
}

class _SuperAdminSystemScreenState extends State<SuperAdminSystemScreen> {
  bool _maintenance = false;
  final _maintenanceMsg = TextEditingController();
  final Map<String, bool> _featureEnabled = {
    for (final key in AppFeatureConfig.allEnabledKeys) key: true,
  };
  final Map<String, TextEditingController> _featureMessages = {
    for (final key in AppFeatureConfig.allEnabledKeys)
      key: TextEditingController(),
  };
  final _pushTitle = TextEditingController();
  final _pushBody = TextEditingController();
  Future<List<SuperAdminBanner>>? _bannersFuture;
  Future<List<SuperAdminNotice>>? _noticesFuture;
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
    for (final c in _featureMessages.values) {
      c.dispose();
    }
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
      final features = settings['featureConfigs'];
      if (features is List) {
        for (final raw in features) {
          if (raw is! Map) continue;
          final row = AppFeatureConfig.fromSuperAdminRow(
            Map<String, dynamic>.from(raw),
          );
          if (row.featureKey.isEmpty) continue;
          _featureEnabled[row.featureKey] = row.isEnabled;
          _featureMessages[row.featureKey]?.text =
              row.disabledMessage ?? '';
        }
      }
      _bannersFuture = widget.service.fetchBanners();
      _noticesFuture = widget.service.fetchNotices();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onFeatureToggle(String featureKey, bool next) async {
    if (!next) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('기능 차단'),
          content: const Text('해당 기능이 모든 사용자에게 즉시 차단됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('차단'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _featureEnabled[featureKey] = next);
  }

  Future<void> _saveFeatureConfigs() async {
    try {
      for (final key in AppFeatureConfig.allEnabledKeys) {
        await widget.service.setFeatureConfig(
          featureKey: key,
          isEnabled: _featureEnabled[key] ?? true,
          disabledMessage: _featureMessages[key]?.text,
        );
      }
      if (mounted) {
        DanjiSnackBar.show(context, '기능별 차단 설정이 저장되었습니다.');
      }
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
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

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: b == null ? '배너 등록' : '배너 수정',
      child: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: sub, decoration: const InputDecoration(labelText: '상단 텍스트')),
            TextField(controller: main, decoration: const InputDecoration(labelText: '메인 텍스트')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: '설명')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('노출'),
              value: active,
              onChanged: (v) => setLocal(() => active = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: superAdminPrimaryFabStyle,
              child: const Text('저장'),
            ),
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

  Future<void> _editNotice([SuperAdminNotice? n]) async {
    final title = TextEditingController(text: n?.title ?? '');
    final content = TextEditingController(text: n?.content ?? '');
    var active = n?.isActive ?? true;

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: n == null ? '전체 공지 등록' : '공지 수정',
      child: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
            TextField(
              controller: content,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '내용'),
            ),
            if (n != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('노출'),
                value: active,
                onChanged: (v) => setLocal(() => active = v),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: superAdminPrimaryFabStyle,
              child: Text(n == null ? '등록' : '저장'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.upsertNotice(
        id: n?.id,
        title: title.text,
        content: content.text,
        isActive: active,
      );
      _load();
      if (mounted) {
        DanjiSnackBar.show(context, n == null ? '공지가 등록되었습니다.' : '공지가 수정되었습니다.');
      }
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
    if (_loading) return const AdminScaffold(body: SuperAdminLoadingBody());

    return AdminScaffold(
      appBar: const DanjiAppBar(title: '시스템'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SuperAdminSectionTitle('점검모드'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('점검모드 활성화'),
                  value: _maintenance,
                  onChanged: (v) => setState(() => _maintenance = v),
                ),
                TextField(
                  controller: _maintenanceMsg,
                  decoration: const InputDecoration(
                    labelText: '점검 안내 메시지',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saveMaintenance,
                  style: superAdminPrimaryFabStyle,
                  child: const Text('저장'),
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
                const SuperAdminSectionTitle('기능별 차단'),
                const SizedBox(height: 4),
                const Text(
                  '전체 점검모드가 켜져 있으면 아래 설정과 관계없이 전체 차단됩니다.\n'
                  '각 토글을 켜면 해당 기능이 정상 운영되고, 끄면 차단됩니다.',
                  style: TextStyle(
                    color: DanjiColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                for (final key in AppFeatureConfig.allEnabledKeys) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(featureLabelKo(key)),
                    subtitle: Text(
                      (_featureEnabled[key] ?? true) ? '운영중' : '차단됨',
                      style: TextStyle(
                        color: (_featureEnabled[key] ?? true)
                            ? SuperAdminUiColors.availableGreen
                            : DanjiColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    value: _featureEnabled[key] ?? true,
                    onChanged: (v) => _onFeatureToggle(key, v),
                  ),
                  TextField(
                    controller: _featureMessages[key],
                    decoration: InputDecoration(
                      labelText: '${featureLabelKo(key)} 안내 문구',
                      hintText: AppFeatureConfig.defaultFeatureDisabledMessage,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _saveFeatureConfigs,
                  style: superAdminPrimaryFabStyle,
                  child: const Text('저장'),
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
                Row(
                  children: [
                    const Expanded(child: SuperAdminSectionTitle('배너 관리')),
                    TextButton(
                      onPressed: () => _editBanner(),
                      child: const Text('추가'),
                    ),
                  ],
                ),
                FutureBuilder<List<SuperAdminBanner>>(
                  future: _bannersFuture,
                  builder: (context, snap) {
                    final list = snap.data ?? [];
                    if (list.isEmpty) {
                      return const Text('배너 없음', style: TextStyle(color: DanjiColors.textSecondary));
                    }
                    return Column(
                      children: list
                          .map(
                            (b) => SuperAdminListCard(
                              icon: Icons.view_carousel_outlined,
                              title: b.mainTitle,
                              subtitle: b.subTitle,
                              titleSuffix: SuperAdminChip(
                                label: b.isActive ? '노출중' : '중지',
                                color: b.isActive
                                    ? SuperAdminUiColors.availableGreen
                                    : DanjiColors.textMuted,
                              ),
                              onTap: () => _editBanner(b),
                            ),
                          )
                          .toList(),
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
                Row(
                  children: [
                    const Expanded(child: SuperAdminSectionTitle('공지사항')),
                    TextButton(
                      onPressed: () => _editNotice(),
                      child: const Text('등록'),
                    ),
                  ],
                ),
                FutureBuilder<List<SuperAdminNotice>>(
                  future: _noticesFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: CircularProgressIndicator(color: DanjiColors.buttonBlue),
                        ),
                      );
                    }
                    final list = snap.data ?? [];
                    if (list.isEmpty) {
                      return const Text('공지 없음', style: TextStyle(color: DanjiColors.textSecondary));
                    }
                    return Column(
                      children: list
                          .map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SectionCard(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        SuperAdminChip(
                                          label: n.isActive ? '노출' : '숨김',
                                          color: n.isActive
                                              ? SuperAdminUiColors.availableGreen
                                              : DanjiColors.textMuted,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        if (n.isGlobal) '전체',
                                        if (n.complexName != null) n.complexName!,
                                        if (n.createdAt != null)
                                          superAdminDateTime.format(n.createdAt!),
                                      ].join(' · '),
                                      style: const TextStyle(
                                        color: DanjiColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (n.content.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        n.content,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: DanjiColors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => _editNotice(n),
                                          child: const Text('수정'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final confirm = await superAdminConfirmDialog(
                                              context,
                                              title: '공지 삭제',
                                              message: '${n.title} 공지를 삭제할까요?',
                                              confirmLabel: '삭제',
                                              danger: true,
                                            );
                                            if (!confirm) return;
                                            await widget.service.deleteNotice(n.id);
                                            _load();
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor: DanjiColors.danger,
                                          ),
                                          child: const Text('삭제'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
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
                const SuperAdminSectionTitle('전체 푸시'),
                const SizedBox(height: 8),
                TextField(
                  controller: _pushTitle,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pushBody,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _pushing ? null : _broadcast,
                  style: superAdminPrimaryFabStyle,
                  child: _pushing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('발송 (최대 200명)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
