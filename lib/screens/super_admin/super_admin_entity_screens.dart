import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

// ── 단지 관리 ────────────────────────────────────────────────
class SuperAdminComplexesScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminComplexesScreen({super.key, required this.service});
  @override
  State<SuperAdminComplexesScreen> createState() =>
      _SuperAdminComplexesScreenState();
}

class _SuperAdminComplexesScreenState extends State<SuperAdminComplexesScreen> {
  Future<List<SuperAdminComplex>>? _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = widget.service.fetchComplexes());

  Future<void> _editor([SuperAdminComplex? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final invite = TextEditingController(text: item?.inviteCode ?? '');
    final adminInvite = TextEditingController(text: item?.adminInviteCode ?? '');
    final biz = TextEditingController(text: item?.businessName ?? '');
    final phone = TextEditingController(text: item?.businessPhone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? '단지 등록' : '단지 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '단지명')),
              TextField(controller: invite, decoration: const InputDecoration(labelText: '입주민 초대코드')),
              TextField(controller: adminInvite, decoration: const InputDecoration(labelText: '관리자 초대코드')),
              TextField(controller: biz, decoration: const InputDecoration(labelText: '업체명')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: '대표전화')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
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
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('단지 등록'),
      ),
      body: _listBody(
        future: _future,
        empty: '등록된 단지가 없습니다.',
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = list[i];
            return SectionCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('차량 ${c.vehicleCount} · 스태프 ${c.staffCount} · 입주민 ${c.residentCount}',
                      style: const TextStyle(color: DanjiColors.textSecondary, fontSize: 12)),
                  if (c.inviteCode != null) Text('입주민코드: ${c.inviteCode}', style: const TextStyle(fontSize: 12)),
                  if (c.adminInviteCode != null) Text('관리자코드: ${c.adminInviteCode}', style: const TextStyle(fontSize: 12)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => _editor(c), child: const Text('수정')),
                      TextButton(
                        onPressed: () async {
                          try {
                            await widget.service.deleteComplex(c.id);
                            _reload();
                          } catch (e) {
                            if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                          }
                        },
                        child: const Text('삭제', style: TextStyle(color: DanjiColors.danger)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── 차량 관리 ────────────────────────────────────────────────
class SuperAdminVehiclesScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminVehiclesScreen({super.key, required this.service});
  @override
  State<SuperAdminVehiclesScreen> createState() =>
      _SuperAdminVehiclesScreenState();
}

class _SuperAdminVehiclesScreenState extends State<SuperAdminVehiclesScreen> {
  Future<List<SuperAdminVehicle>>? _vehiclesFuture;
  Future<List<SuperAdminComplex>>? _complexesFuture;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _vehiclesFuture = widget.service.fetchVehicles();
      _complexesFuture = widget.service.fetchComplexes();
    });
  }

  Future<void> _editor(List<SuperAdminComplex> complexes, [SuperAdminVehicle? v]) async {
    final name = TextEditingController(text: v?.modelName ?? '');
    final carNo = TextEditingController(text: v?.carNumber ?? '');
    final price = TextEditingController(text: '${v?.pricePerHour ?? 0}');
    var complexId = v?.complexId ?? (complexes.isNotEmpty ? complexes.first.id : '');
    var available = v?.isAvailable ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v == null ? '차량 등록' : '차량 수정', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: complexId.isEmpty ? null : complexId,
                  decoration: const InputDecoration(labelText: '단지'),
                  items: complexes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (val) => setLocal(() => complexId = val ?? complexId),
                ),
                TextField(controller: name, decoration: const InputDecoration(labelText: '차량명')),
                TextField(controller: carNo, decoration: const InputDecoration(labelText: '차량번호')),
                TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '시간당 가격')),
                SwitchListTile(title: const Text('가용'), value: available, onChanged: (val) => setLocal(() => available = val)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
              ],
            ),
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      floatingActionButton: FloatingActionButton.extended(
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
      body: FutureBuilder<List<SuperAdminComplex>>(
        future: _complexesFuture,
        builder: (context, cxSnap) {
          final complexes = cxSnap.data ?? [];
          return _listBody(
            future: _vehiclesFuture,
            empty: '등록된 차량이 없습니다.',
            builder: (list) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final v = list[i];
                return SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${v.modelName} · ${v.complexName}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(v.carNumber ?? '-', style: const TextStyle(color: DanjiColors.textSecondary)),
                      Wrap(spacing: 6, children: [
                        SuperAdminChip(label: v.inUse ? '대여중' : (v.isAvailable ? '가용' : '비가용'),
                            color: v.inUse ? DanjiColors.danger : const Color(0xFF22C55E)),
                        SuperAdminChip(label: '₩${superAdminWon.format(v.pricePerHour)}/h', color: DanjiColors.primaryBlue),
                      ]),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => _editor(complexes, v), child: const Text('수정')),
                          TextButton(
                            onPressed: () async {
                              try {
                                await widget.service.deleteVehicle(v.id);
                                _reload();
                              } catch (e) {
                                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                              }
                            },
                            child: const Text('삭제', style: TextStyle(color: DanjiColors.danger)),
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

  @override
  Widget build(BuildContext context) {
    return _listBody(
      future: _future,
      empty: '스태프가 없습니다.',
      builder: (list) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = list[i];
          return SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${s.complexName} · ${s.email ?? ''}', style: const TextStyle(fontSize: 12, color: DanjiColors.textSecondary)),
                SuperAdminChip(label: s.approved ? '승인' : '대기', color: s.approved ? const Color(0xFF22C55E) : DanjiColors.danger),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!s.approved)
                      TextButton(
                        onPressed: () async {
                          await widget.service.setStaffApproved(s.userId, true);
                          _reload();
                        },
                        child: const Text('승인'),
                      ),
                    if (s.approved)
                      TextButton(
                        onPressed: () async {
                          await widget.service.setStaffApproved(s.userId, false);
                          _reload();
                        },
                        child: const Text('거절'),
                      ),
                    TextButton(
                      onPressed: () async {
                        final cx = await _complexesFuture;
                        if (!mounted || cx == null || cx.isEmpty) return;
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: const Text('단지 변경'),
                            children: cx.map((c) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, c.id),
                              child: Text(c.name),
                            )).toList(),
                          ),
                        );
                        if (picked != null) {
                          await widget.service.setStaffComplex(s.userId, picked);
                          _reload();
                        }
                      },
                      child: const Text('단지변경'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await widget.service.deleteStaff(s.userId);
                        _reload();
                      },
                      child: const Text('삭제', style: TextStyle(color: DanjiColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
  Future<List<SuperAdminResident>>? _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = widget.service.fetchResidents());

  @override
  Widget build(BuildContext context) {
    return _listBody(
      future: _future,
      empty: '입주민이 없습니다.',
      builder: (list) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = list[i];
          return SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.fullName ?? r.email ?? '이름 미등록', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${r.complexName} ${r.building ?? ''}동 ${r.unit ?? ''}호', style: const TextStyle(fontSize: 12, color: DanjiColors.textSecondary)),
                Wrap(spacing: 6, children: [
                  SuperAdminChip(label: r.approved ? '승인' : '대기', color: r.approved ? const Color(0xFF22C55E) : DanjiColors.danger),
                  if (r.licenseVerified) const SuperAdminChip(label: '면허승인', color: DanjiColors.primaryBlue),
                ]),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!r.approved)
                      TextButton(onPressed: () async { await widget.service.setResidentApproved(r.userId, true); _reload(); }, child: const Text('승인')),
                    if (r.approved)
                      TextButton(onPressed: () async { await widget.service.setResidentApproved(r.userId, false); _reload(); }, child: const Text('거절')),
                    if (!r.licenseVerified)
                      TextButton(onPressed: () async { await widget.service.forceLicenseApproved(r.userId); _reload(); }, child: const Text('면허강제승인')),
                    TextButton(onPressed: () async { await widget.service.setBlacklist(r.userId, true); _reload(); }, child: const Text('블랙리스트')),
                    TextButton(onPressed: () async { await widget.service.deleteResident(r.userId); _reload(); }, child: const Text('삭제', style: TextStyle(color: DanjiColors.danger))),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _listBody<T>({
  required Future<List<T>>? future,
  required String empty,
  required Widget Function(List<T>) builder,
}) {
  return FutureBuilder<List<T>>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return Center(child: Text(friendlySuperAdminError(snap.error!)));
      }
      final list = snap.data ?? [];
      if (list.isEmpty) {
        return Center(child: Text(empty, style: const TextStyle(color: DanjiColors.textSecondary)));
      }
      return builder(list);
    },
  );
}
