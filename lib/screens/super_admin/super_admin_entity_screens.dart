import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';
import 'super_admin_nav.dart';
import 'super_admin_resident_detail_screen.dart';

enum SuperAdminApprovalFilter { all, approved, pending }

extension on SuperAdminApprovalFilter {
  String get label {
    switch (this) {
      case SuperAdminApprovalFilter.all:
        return '전체';
      case SuperAdminApprovalFilter.approved:
        return '승인';
      case SuperAdminApprovalFilter.pending:
        return '대기';
    }
  }
}

// ── 단지 관리 ────────────────────────────────────────────────
class SuperAdminComplexesScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminComplexesScreen({super.key, required this.service});
  @override
  State<SuperAdminComplexesScreen> createState() =>
      _SuperAdminComplexesScreenState();
}

class _SuperAdminComplexesScreenState extends State<SuperAdminComplexesScreen> {
  List<SuperAdminComplex> _complexes = [];
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await widget.service.fetchComplexes();
      if (!mounted) return;
      setState(() {
        _complexes = data;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _regenerateInvite(SuperAdminComplex item, {required bool admin}) async {
    final code = generateSuperAdminInviteCode();
    try {
      await widget.service.upsertComplex(
        id: item.id,
        name: item.name,
        inviteCode: admin ? item.inviteCode : code,
        adminInviteCode: admin ? code : item.adminInviteCode,
        businessName: item.businessName,
        businessPhone: item.businessPhone,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      DanjiSnackBar.show(
        context,
        admin ? '관리자 초대코드가 재발급되었습니다.' : '입주민 초대코드가 재발급되었습니다.',
      );
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _editor([SuperAdminComplex? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final invite = TextEditingController(text: item?.inviteCode ?? '');
    final adminInvite = TextEditingController(text: item?.adminInviteCode ?? '');
    final biz = TextEditingController(text: item?.businessName ?? '');
    final phone = TextEditingController(text: item?.businessPhone ?? '');

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: item == null ? '단지 등록' : '단지 수정',
      child: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '단지명')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: invite,
                    decoration: const InputDecoration(labelText: '입주민 초대코드'),
                  ),
                ),
                IconButton(
                  tooltip: '자동 발급',
                  onPressed: () {
                    invite.text = generateSuperAdminInviteCode();
                    setLocal(() {});
                  },
                  icon: const Icon(Icons.autorenew, color: DanjiColors.buttonBlue),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: adminInvite,
                    decoration: const InputDecoration(labelText: '관리자 초대코드'),
                  ),
                ),
                IconButton(
                  tooltip: '자동 발급',
                  onPressed: () {
                    adminInvite.text = generateSuperAdminInviteCode();
                    setLocal(() {});
                  },
                  icon: const Icon(Icons.autorenew, color: DanjiColors.buttonBlue),
                ),
              ],
            ),
            TextField(controller: biz, decoration: const InputDecoration(labelText: '업체명')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: '대표전화')),
            const SizedBox(height: 16),
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
      await widget.service.upsertComplex(
        id: item?.id,
        name: name.text,
        inviteCode: invite.text,
        adminInviteCode: adminInvite.text,
        businessName: biz.text,
        businessPhone: phone.text,
      );
      if (!mounted) return;
      await _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _openDetail(SuperAdminComplex c) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: c.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '차량 ${c.vehicleCount} · 스태프 ${c.staffCount} · 입주민 ${c.residentCount}',
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
          if (c.inviteCode != null) ...[
            const SizedBox(height: 8),
            Text('입주민코드: ${c.inviteCode}', style: const TextStyle(fontSize: 13)),
          ],
          if (c.adminInviteCode != null)
            Text('관리자코드: ${c.adminInviteCode}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _regenerateInvite(c, admin: false);
            },
            child: const Text('입주민코드 재발급'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _regenerateInvite(c, admin: true);
            },
            child: const Text('관리자코드 재발급'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _editor(c);
            },
            style: superAdminPrimaryFabStyle,
            child: const Text('수정'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await superAdminConfirmDialog(
                context,
                title: '단지 삭제',
                message: '${c.name} 단지를 삭제할까요?',
                confirmLabel: '삭제',
                danger: true,
              );
              if (!confirm) return;
              try {
                await widget.service.deleteComplex(c.id);
                if (!mounted) return;
                await _reload();
              } catch (e) {
                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
              }
            },
            style: DanjiTheme.dangerButton,
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SuperAdminLoadingBody();
    if (_loadError != null) {
      return Center(child: Text(friendlySuperAdminError(_loadError!)));
    }
    if (_complexes.isEmpty) {
      return RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            SuperAdminEmptyState('등록된 단지가 없습니다.'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: DanjiColors.buttonBlue,
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: _complexes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final c = _complexes[i];
          return SuperAdminListCard(
            icon: Icons.apartment_outlined,
            title: c.name,
            subtitle: '차량 ${c.vehicleCount} · 스태프 ${c.staffCount} · 입주민 ${c.residentCount}\n'
                '${c.inviteCode != null ? '입주민코드 ${c.inviteCode}' : '입주민코드 미설정'}',
            onTap: () => _openDetail(c),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '단지 관리'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DanjiColors.buttonBlue,
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('단지 등록'),
      ),
      body: _buildBody(),
    );
  }
}

// ── 차량 관리 ────────────────────────────────────────────────
class SuperAdminVehiclesScreen extends StatefulWidget {
  final SuperAdminService service;
  final SuperAdminVehicleFilter initialFilter;

  const SuperAdminVehiclesScreen({
    super.key,
    required this.service,
    this.initialFilter = SuperAdminVehicleFilter.all,
  });

  @override
  State<SuperAdminVehiclesScreen> createState() =>
      _SuperAdminVehiclesScreenState();
}

class _SuperAdminVehiclesScreenState extends State<SuperAdminVehiclesScreen> {
  Future<List<SuperAdminVehicle>>? _vehiclesFuture;
  Future<List<SuperAdminComplex>>? _complexesFuture;
  late SuperAdminVehicleFilter _filter;
  String? _complexFilter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _reload();
  }

  @override
  void didUpdateWidget(covariant SuperAdminVehiclesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  void _reload() {
    setState(() {
      _vehiclesFuture = widget.service.fetchVehicles();
      _complexesFuture = widget.service.fetchComplexes();
    });
  }

  List<SuperAdminVehicle> _applyFilter(List<SuperAdminVehicle> list) {
    var result = list;
    if (_complexFilter != null) {
      result = result.where((v) => v.complexId == _complexFilter).toList();
    }
    switch (_filter) {
      case SuperAdminVehicleFilter.available:
        return result.where((v) => !v.inUse && v.isAvailable).toList();
      case SuperAdminVehicleFilter.inUse:
        return result.where((v) => v.inUse).toList();
      case SuperAdminVehicleFilter.all:
        return result;
    }
  }

  Future<void> _editor(List<SuperAdminComplex> complexes, [SuperAdminVehicle? v]) async {
    final name = TextEditingController(text: v?.modelName ?? '');
    final carNo = TextEditingController(text: v?.carNumber ?? '');
    final price = TextEditingController(text: '${v?.pricePerHour ?? 0}');
    var complexId = v?.complexId ?? (complexes.isNotEmpty ? complexes.first.id : '');
    var available = v?.isAvailable ?? true;

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: v == null ? '차량 등록' : '차량 수정',
      child: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: complexId.isEmpty ? null : complexId,
              decoration: const InputDecoration(labelText: '단지'),
              items: complexes
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (val) => setLocal(() => complexId = val ?? complexId),
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: '차량명')),
            TextField(controller: carNo, decoration: const InputDecoration(labelText: '차량번호')),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '시간당 가격'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('가용'),
              value: available,
              onChanged: (val) => setLocal(() => available = val),
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
    if (ok != true || complexId.isEmpty) return;
    try {
      await widget.service.upsertVehicle(
        id: v?.id,
        complexId: complexId,
        modelName: name.text,
        carNumber: carNo.text,
        pricePerHour: int.tryParse(price.text) ?? 0,
        isAvailable: available,
      );
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _openDetail(SuperAdminVehicle v, List<SuperAdminComplex> complexes) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: v.modelName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${v.complexName} · ${v.carNumber ?? '번호 미등록'}',
              style: const TextStyle(color: DanjiColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              SuperAdminChip(
                label: v.inUse ? '대여중' : (v.isAvailable ? '가용' : '비가용'),
                color: v.inUse
                    ? DanjiColors.danger
                    : (v.isAvailable ? SuperAdminUiColors.availableGreen : DanjiColors.textMuted),
              ),
              SuperAdminChip(
                label: '₩${superAdminWon.format(v.pricePerHour)}/h',
                color: DanjiColors.buttonBlue,
              ),
            ],
          ),
          if (v.inUse && v.currentRenterName != null) ...[
            const SizedBox(height: 8),
            Text('대여: ${v.currentRenterName}'),
          ],
          const SizedBox(height: 16),
          if (!v.inUse)
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await widget.service.upsertVehicle(
                    id: v.id,
                    complexId: v.complexId,
                    modelName: v.modelName,
                    carNumber: v.carNumber,
                    pricePerHour: v.pricePerHour,
                    isAvailable: !v.isAvailable,
                  );
                  _reload();
                } catch (e) {
                  if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                }
              },
              child: Text(v.isAvailable ? '비가용 전환' : '가용 전환'),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _editor(complexes, v);
            },
            style: superAdminPrimaryFabStyle,
            child: const Text('수정'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await superAdminConfirmDialog(
                context,
                title: '차량 삭제',
                message: '${v.modelName} 차량을 삭제할까요?',
                confirmLabel: '삭제',
                danger: true,
              );
              if (!confirm) return;
              try {
                await widget.service.deleteVehicle(v.id);
                _reload();
              } catch (e) {
                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
              }
            },
            style: DanjiTheme.dangerButton,
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '차량 관리'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DanjiColors.buttonBlue,
        onPressed: () async {
          final cx = await _complexesFuture;
          if (!mounted || cx == null || cx.isEmpty) {
            DanjiSnackBar.show(context, '단지를 먼저 등록해주세요.');
            return;
          }
          await _editor(cx);
        },
        icon: const Icon(Icons.add),
        label: const Text('차량 등록'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                SuperAdminVehicleFilterBar(
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<SuperAdminComplex>>(
                  future: _complexesFuture,
                  builder: (context, cxSnap) {
                    final complexes = cxSnap.data ?? [];
                    return SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: _complexFilter,
                          hint: const Text('전체 단지'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('전체 단지'),
                            ),
                            ...complexes.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _complexFilter = v),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SuperAdminComplex>>(
              future: _complexesFuture,
              builder: (context, cxSnap) {
                final complexes = cxSnap.data ?? [];
                return superAdminListBody(
                  future: _vehiclesFuture,
                  empty: '해당 조건의 차량이 없습니다.',
                  onRefresh: () async => _reload(),
                  builder: (list) {
                    final filtered = _applyFilter(list);
                    if (filtered.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          SuperAdminEmptyState('해당 조건의 차량이 없습니다.'),
                        ],
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = filtered[i];
                        return SuperAdminListCard(
                          icon: Icons.directions_car_outlined,
                          title: '${v.modelName} · ${v.complexName}',
                          subtitle: '${v.carNumber ?? '번호 미등록'} · '
                              '${v.inUse ? '대여중' : (v.isAvailable ? '가용' : '비가용')} · '
                              '₩${superAdminWon.format(v.pricePerHour)}/h',
                          trailing: Icon(
                            v.inUse
                                ? Icons.navigation_outlined
                                : (v.isAvailable ? Icons.check_circle : Icons.pause_circle),
                            color: v.inUse
                                ? SuperAdminUiColors.inUseOrange
                                : (v.isAvailable
                                    ? SuperAdminUiColors.availableGreen
                                    : DanjiColors.textMuted),
                          ),
                          onTap: () => _openDetail(v, complexes),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 스태프 관리 ───────────────────────────────────────────────
class SuperAdminStaffScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminStaffScreen({super.key, required this.service});
  @override
  State<SuperAdminStaffScreen> createState() => _SuperAdminStaffScreenState();
}

class _SuperAdminStaffScreenState extends State<SuperAdminStaffScreen> {
  Future<List<SuperAdminStaff>>? _future;
  Future<List<SuperAdminComplex>>? _complexesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.service.fetchStaff();
      _complexesFuture = widget.service.fetchComplexes();
    });
  }

  Future<void> _openDetail(SuperAdminStaff s) async {
    final cx = await _complexesFuture ?? [];
    if (!mounted) return;

    await showSuperAdminBottomSheet<void>(
      context,
      title: s.displayName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${s.complexName} · ${s.email ?? ''}',
              style: const TextStyle(color: DanjiColors.textSecondary)),
          const SizedBox(height: 8),
          SuperAdminChip(
            label: s.approved ? '승인' : '대기',
            color: s.approved ? SuperAdminUiColors.availableGreen : DanjiColors.danger,
          ),
          const SizedBox(height: 16),
          if (!s.approved)
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await widget.service.setStaffApproved(s.userId, true);
                _reload();
              },
              style: superAdminPrimaryFabStyle,
              child: const Text('승인'),
            ),
          if (s.approved) ...[
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                await widget.service.setStaffApproved(s.userId, false);
                _reload();
              },
              child: const Text('거절'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (cx.isEmpty) return;
              final picked = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('단지 변경'),
                  children: cx
                      .map(
                        (c) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, c.id),
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                ),
              );
              if (picked != null) {
                await widget.service.setStaffComplex(s.userId, picked);
                _reload();
              }
            },
            child: const Text('단지 변경'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await superAdminConfirmDialog(
                context,
                title: '스태프 삭제',
                message: '${s.displayName} 스태프를 삭제할까요?',
                confirmLabel: '삭제',
                danger: true,
              );
              if (!confirm) return;
              await widget.service.deleteStaff(s.userId);
              _reload();
            },
            style: DanjiTheme.dangerButton,
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '스태프 관리'),
      body: superAdminListBody(
        future: _future,
        empty: '스태프가 없습니다.',
        onRefresh: () async => _reload(),
        builder: (list) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final s = list[i];
            return SuperAdminListCard(
              icon: Icons.badge_outlined,
              title: s.displayName,
              subtitle: '${s.complexName} · ${s.email ?? ''}',
              trailing: SuperAdminChip(
                label: s.approved ? '승인' : '대기',
                color: s.approved ? SuperAdminUiColors.availableGreen : DanjiColors.danger,
              ),
              onTap: () => _openDetail(s),
            );
          },
        ),
      ),
    );
  }
}

// ── 입주민 관리 ───────────────────────────────────────────────
class SuperAdminResidentsScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminResidentsScreen({super.key, required this.service});
  @override
  State<SuperAdminResidentsScreen> createState() =>
      _SuperAdminResidentsScreenState();
}

class _SuperAdminResidentsScreenState extends State<SuperAdminResidentsScreen> {
  List<SuperAdminResident> _allResidents = [];
  List<SuperAdminComplex> _complexes = [];
  Map<String, Set<String>> _reservationIdsByUser = {};
  Object? _loadError;
  bool _loading = true;

  String? _complexFilter;
  SuperAdminApprovalFilter _approvalFilter = SuperAdminApprovalFilter.all;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final results = await Future.wait([
        widget.service.fetchResidents(),
        widget.service.fetchComplexes(),
        widget.service.fetchReservationUserIndex(),
      ]);
      if (!mounted) return;
      setState(() {
        _allResidents = results[0] as List<SuperAdminResident>;
        _complexes = results[1] as List<SuperAdminComplex>;
        _reservationIdsByUser = results[2] as Map<String, Set<String>>;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  bool _matchesSearch(SuperAdminResident r, String query) {
    if (query.isEmpty) return true;

    final name = (r.fullName ?? '').toLowerCase();
    if (name.contains(query)) return true;

    final phone = (r.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final qPhone = query.replaceAll(RegExp(r'\D'), '');
    if (qPhone.isNotEmpty && phone.contains(qPhone)) return true;

    final reservationIds = _reservationIdsByUser[r.userId] ?? const {};
    return reservationIds.any((id) => id.toLowerCase().contains(query));
  }

  List<SuperAdminResident> _filter(List<SuperAdminResident> all) {
    final query = _searchController.text.trim().toLowerCase();
    return all.where((r) {
      if (!_matchesSearch(r, query)) return false;
      if (_complexFilter != null &&
          _complexFilter!.isNotEmpty &&
          r.complexId != _complexFilter) {
        return false;
      }
      switch (_approvalFilter) {
        case SuperAdminApprovalFilter.approved:
          return r.approved;
        case SuperAdminApprovalFilter.pending:
          return !r.approved;
        case SuperAdminApprovalFilter.all:
          return true;
      }
    }).toList();
  }

  Future<void> _openDetail(SuperAdminResident r) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SuperAdminResidentDetailScreen(
          service: widget.service,
          resident: r,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _buildList(List<SuperAdminResident> filtered) {
    if (filtered.isEmpty) {
      final emptyMessage = _allResidents.isEmpty
          ? '입주민이 없습니다.'
          : '조건에 맞는 입주민이 없습니다.';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          SuperAdminEmptyState(emptyMessage),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = filtered[i];
        return SuperAdminListCard(
          icon: Icons.person_outline,
          title: r.fullName ?? r.email ?? '이름 미등록',
          subtitle: '${r.complexName} ${r.building ?? ''}동 ${r.unit ?? ''}호',
          trailing: Wrap(
            spacing: 4,
            children: [
              if (r.isBlacklisted)
                const SuperAdminChip(label: 'BL', color: DanjiColors.danger),
              SuperAdminChip(
                label: r.approved ? '승인' : '대기',
                color: r.approved
                    ? SuperAdminUiColors.availableGreen
                    : DanjiColors.danger,
              ),
            ],
          ),
          onTap: () => _openDetail(r),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminScaffold(
        appBar: DanjiAppBar(title: '입주민 관리'),
        body: SuperAdminLoadingBody(),
      );
    }
    if (_loadError != null) {
      return AdminScaffold(
        appBar: const DanjiAppBar(title: '입주민 관리'),
        body: Center(child: Text(friendlySuperAdminError(_loadError!))),
      );
    }

    final filtered = _filter(_allResidents);
    final sortedComplexes = List<SuperAdminComplex>.from(_complexes)
      ..sort((a, b) => a.name.compareTo(b.name));

    return AdminScaffold(
      appBar: const DanjiAppBar(title: '입주민 관리'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                SectionCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '이름, 전화번호, 예약번호 검색',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _complexFilter,
                      hint: const Text('전체 단지'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('전체 단지'),
                        ),
                        ...sortedComplexes.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _complexFilter = v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SuperAdminApprovalFilter>(
                      isExpanded: true,
                      value: _approvalFilter,
                      items: SuperAdminApprovalFilter.values
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _approvalFilter = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: DanjiColors.buttonBlue,
              onRefresh: _reload,
              child: _buildList(filtered),
            ),
          ),
        ],
      ),
    );
  }
}
