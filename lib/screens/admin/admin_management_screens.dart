import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/admin_reservation_card_extras.dart';
import '../../widgets/return_inspection_photo_compare.dart';
import '../../widgets/section_card.dart';
import 'admin_vehicle_form_screen.dart';

/// complexes.name 조인값 우선, 없으면 관리자 프로필 단지명
String _vehicleComplexLabel(AdminVehicleDetail vehicle, StaffProfile profile) {
  final fromVehicle = vehicle.complexName?.trim();
  if (fromVehicle != null && fromVehicle.isNotEmpty) return fromVehicle;
  final fromProfile = profile.complexName?.trim();
  if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
  return '단지';
}

class AdminVehicleManageScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminVehicleManageScreen({super.key, required this.profile});

  @override
  State<AdminVehicleManageScreen> createState() =>
      _AdminVehicleManageScreenState();
}

class _AdminVehicleManageScreenState extends State<AdminVehicleManageScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  Future<List<AdminVehicleDetail>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchVehicles(widget.profile.complexId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '차량 관리'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DanjiColors.buttonBlue,
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AdminVehicleFormScreen(profile: widget.profile),
            ),
          );
          if (ok == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('차량 등록'),
      ),
      body: FutureBuilder<List<AdminVehicleDetail>>(
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
            return const Center(child: Text('등록된 차량이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final v = list[index];
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    v.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_vehicleComplexLabel(v, widget.profile)} · '
                    '${v.vehicleType} · ${v.fuelType ?? '-'} · '
                    '₩${_won.format(v.pricePerHour)}/h\n'
                    '${v.carNumber ?? '번호 미등록'} · ${v.parkingLocation ?? '주차 미등록'}',
                  ),
                  trailing: Icon(
                    v.isAvailable ? Icons.check_circle : Icons.pause_circle,
                    color: v.isAvailable
                        ? const Color(0xFF43A047)
                        : DanjiColors.textMuted,
                  ),
                  onTap: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AdminVehicleFormScreen(
                          profile: widget.profile,
                          initial: v,
                        ),
                      ),
                    );
                    if (ok == true) _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminInsuranceScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminInsuranceScreen({super.key, required this.profile});

  @override
  State<AdminInsuranceScreen> createState() => _AdminInsuranceScreenState();
}

class _AdminInsuranceScreenState extends State<AdminInsuranceScreen> {
  final _admin = AdminService();
  final _date = DateFormat('yyyy-MM-dd');
  Future<List<AdminVehicleDetail>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchVehicles(widget.profile.complexId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '보험 관리'),
      body: FutureBuilder<List<AdminVehicleDetail>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('등록된 차량이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final v = list[index];
              final expired = v.isInsuranceExpired;
              final missing = !v.hasInsurance;
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    missing
                        ? '${_vehicleComplexLabel(v, widget.profile)} · 보험 미등록'
                        : '${_vehicleComplexLabel(v, widget.profile)}\n'
                            '${v.insuranceCompany}\n'
                            '증권 ${v.insurancePolicyNumber}\n'
                            '만료 ${v.insuranceExpiresAt != null ? _date.format(v.insuranceExpiresAt!) : '-'}',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (missing
                              ? DanjiColors.accentRed
                              : expired
                                  ? const Color(0xFFFB8C00)
                                  : const Color(0xFF43A047))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      missing
                          ? '미등록'
                          : expired
                              ? '만료'
                              : '정상',
                      style: TextStyle(
                        color: missing
                            ? DanjiColors.accentRed
                            : expired
                                ? const Color(0xFFFB8C00)
                                : const Color(0xFF43A047),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AdminVehicleFormScreen(
                          profile: widget.profile,
                          initial: v,
                        ),
                      ),
                    );
                    _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminPriceScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminPriceScreen({super.key, required this.profile});

  @override
  State<AdminPriceScreen> createState() => _AdminPriceScreenState();
}

class _AdminPriceScreenState extends State<AdminPriceScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  Future<List<AdminVehicleDetail>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchVehicles(widget.profile.complexId);
    });
  }

  Future<void> _editPrice(AdminVehicleDetail vehicle) async {
    final controller = TextEditingController(text: '${vehicle.pricePerHour}');
    final price = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${vehicle.name} 가격'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '시간당 가격 (원)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 0) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (price == null) return;

    try {
      await _admin.updateVehicle(
        AdminVehicleDetail(
          id: vehicle.id,
          complexId: vehicle.complexId,
          complexName: vehicle.complexName,
          name: vehicle.name,
          vehicleType: vehicle.vehicleType,
          fuelType: vehicle.fuelType,
          pricePerHour: price,
          parkingLocation: vehicle.parkingLocation,
          carNumber: vehicle.carNumber,
          ownerName: vehicle.ownerName,
          isAvailable: vehicle.isAvailable,
          insuranceCompany: vehicle.insuranceCompany,
          insurancePolicyNumber: vehicle.insurancePolicyNumber,
          insuranceExpiresAt: vehicle.insuranceExpiresAt,
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAdminError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '가격 관리'),
      body: FutureBuilder<List<AdminVehicleDetail>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final v = list[index];
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${_vehicleComplexLabel(v, widget.profile)} · '
                    '${v.vehicleType} · ${v.fuelType ?? '-'}',
                  ),
                  trailing: Text(
                    '₩${_won.format(v.pricePerHour)}/h',
                    style: const TextStyle(
                      color: DanjiColors.buttonBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () => _editPrice(v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminVehicleLocationScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminVehicleLocationScreen({super.key, required this.profile});

  @override
  State<AdminVehicleLocationScreen> createState() =>
      _AdminVehicleLocationScreenState();
}

class _AdminVehicleLocationScreenState extends State<AdminVehicleLocationScreen> {
  final _admin = AdminService();
  final _time = DateFormat('yyyy-MM-dd HH:mm');
  Future<List<AdminVehicleDetail>>? _vehiclesFuture;
  Future<List<AdminReservationRow>>? _reservationsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _vehiclesFuture = _admin.fetchVehicles(widget.profile.complexId);
      _reservationsFuture =
          _admin.fetchOperatingReservations(widget.profile.complexId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '차량 위치'),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<AdminReservationRow>>(
          future: _reservationsFuture,
          builder: (context, resSnap) {
            final operating = resSnap.data ?? [];
            return FutureBuilder<List<AdminVehicleDetail>>(
              future: _vehiclesFuture,
              builder: (context, vehSnap) {
                final vehicles = vehSnap.data ?? [];
                if (resSnap.connectionState == ConnectionState.waiting &&
                    vehSnap.connectionState == ConnectionState.waiting) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator()),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      '대여 중 차량',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (operating.isEmpty)
                      const SectionCard(
                        child: Text('현재 대여 중인 차량이 없습니다.'),
                      )
                    else
                      ...operating.map((r) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.vehicleName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '번호 ${r.carNumber ?? '-'} · 예약 ${r.id}',
                                  style: const TextStyle(
                                    color: DanjiColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                    const Text(
                      '차량별 최근 위치',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...vehicles.map((v) {
                      final hasCoords =
                          v.lastLatitude != null && v.lastLongitude != null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: DanjiColors.buttonBlue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      v.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('주차: ${v.parkingLocation ?? '미등록'}'),
                              if (hasCoords)
                                Text(
                                  '좌표: ${v.lastLatitude!.toStringAsFixed(5)}, '
                                  '${v.lastLongitude!.toStringAsFixed(5)}',
                                ),
                              if (v.lastLocationUpdatedAt != null)
                                Text(
                                  '갱신: ${_time.format(v.lastLocationUpdatedAt!)}',
                                  style: const TextStyle(
                                    color: DanjiColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              if (!hasCoords)
                                const Text(
                                  'GPS 좌표 없음 — 주차 위치 기준으로 확인',
                                  style: TextStyle(
                                    color: DanjiColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AdminReturnInspectionScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminReturnInspectionScreen({super.key, required this.profile});

  @override
  State<AdminReturnInspectionScreen> createState() =>
      _AdminReturnInspectionScreenState();
}

class _AdminReturnInspectionScreenState
    extends State<AdminReturnInspectionScreen> {
  final _admin = AdminService();
  final _date = DateFormat('yyyy-MM-dd HH:mm');
  Future<List<AdminReservationRow>>? _pendingFuture;
  Future<List<AdminReservationRow>>? _completedFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      // 검수 대기: 고객 반납 완료(returned), 관리자 미확인
      _pendingFuture = _admin.fetchReturnInspections(
        widget.profile.complexId,
        status: 'returned',
      );
      // 검수 완료: 관리자 검수 완료 버튼 처리(completed)
      _completedFuture = _admin.fetchReturnInspections(
        widget.profile.complexId,
        status: 'completed',
      );
    });
  }

  Future<void> _complete(AdminReservationRow row) async {
    try {
      await _admin.completeReturnInspection(row.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반납 검수가 완료되었습니다.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAdminError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AdminScaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DanjiAppBar(title: '반납 검수'),
              Material(
                color: DanjiColors.background,
                child: TabBar(
                  labelColor: DanjiColors.buttonBlue,
                  unselectedLabelColor: DanjiColors.textMuted,
                  indicatorColor: DanjiColors.buttonBlue,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: '검수 대기'),
                    Tab(text: '검수 완료'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          clipBehavior: Clip.hardEdge,
          children: [
            _ReturnInspectionListTab(
              future: _pendingFuture,
              emptyMessage: '검수 대기 중인 반납 차량이 없습니다.',
              dateFormat: _date,
              admin: _admin,
              showCompleteButton: true,
              onComplete: _complete,
              onChanged: _reload,
            ),
            _CompletedReturnInspectionTab(
              future: _completedFuture,
              dateFormat: _date,
              admin: _admin,
              onChanged: _reload,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoShowReturnBadge extends StatelessWidget {
  const _NoShowReturnBadge();

  static const _orange = Color(0xFFFF6D00);
  static const _orangeDark = Color(0xFFE65100);
  static const _orangeBg = Color(0xFFFFF3E0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _orangeBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _orange.withValues(alpha: 0.65),
            width: 1.2,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_outlined, size: 14, color: _orangeDark),
            SizedBox(width: 4),
            Text(
              '노쇼반납',
              style: TextStyle(
                color: _orangeDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _InspectionDateFilterKind { all, inspectionDate, reservationDate }

class _CompletedReturnInspectionTab extends StatefulWidget {
  final Future<List<AdminReservationRow>>? future;
  final DateFormat dateFormat;
  final AdminService admin;
  final VoidCallback? onChanged;

  const _CompletedReturnInspectionTab({
    required this.future,
    required this.dateFormat,
    required this.admin,
    this.onChanged,
  });

  @override
  State<_CompletedReturnInspectionTab> createState() =>
      _CompletedReturnInspectionTabState();
}

class _CompletedReturnInspectionTabState
    extends State<_CompletedReturnInspectionTab> {
  _InspectionDateFilterKind _filterKind = _InspectionDateFilterKind.all;
  DateTime? _filterDate;

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  List<AdminReservationRow> _applyFilter(List<AdminReservationRow> rows) {
    if (_filterKind == _InspectionDateFilterKind.all || _filterDate == null) {
      return rows;
    }

    bool sameDay(DateTime? value) {
      if (value == null) return false;
      final local = value.toLocal();
      return local.year == _filterDate!.year &&
          local.month == _filterDate!.month &&
          local.day == _filterDate!.day;
    }

    return rows.where((row) {
      switch (_filterKind) {
        case _InspectionDateFilterKind.inspectionDate:
          return sameDay(row.updatedAt);
        case _InspectionDateFilterKind.reservationDate:
          return sameDay(row.startAt);
        case _InspectionDateFilterKind.all:
          return true;
      }
    }).toList();
  }

  Widget _buildFilterHeader(String dateLabel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InspectionFilterChip(
            label: '전체',
            selected: _filterKind == _InspectionDateFilterKind.all,
            onTap: () => setState(() {
              _filterKind = _InspectionDateFilterKind.all;
              _filterDate = null;
            }),
          ),
          _InspectionFilterChip(
            label: '검수일자',
            selected: _filterKind == _InspectionDateFilterKind.inspectionDate,
            onTap: () => setState(() {
              _filterKind = _InspectionDateFilterKind.inspectionDate;
              _filterDate ??= DateTime.now();
            }),
          ),
          _InspectionFilterChip(
            label: '예약일자',
            selected: _filterKind == _InspectionDateFilterKind.reservationDate,
            onTap: () => setState(() {
              _filterKind = _InspectionDateFilterKind.reservationDate;
              _filterDate ??= DateTime.now();
            }),
          ),
          if (_filterKind != _InspectionDateFilterKind.all)
            OutlinedButton.icon(
              onPressed: _pickFilterDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(dateLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: DanjiColors.buttonBlue,
                side: const BorderSide(color: DanjiColors.buttonBlue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _filterDate == null
        ? '날짜 선택'
        : DateFormat('yyyy-MM-dd').format(_filterDate!);

    return FutureBuilder<List<AdminReservationRow>>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text(friendlyAdminError(snap.error!)));
        }

        final filtered = _applyFilter(snap.data ?? []);

        if (filtered.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _buildFilterHeader(dateLabel),
              const SizedBox(height: 80),
              const Center(
                child: Text('검수 완료된 반납 차량이 없습니다.'),
              ),
            ],
          );
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: filtered.length + 1,
          separatorBuilder: (context, index) {
            if (index == 0) return const SizedBox(height: 12);
            return const SizedBox(height: 10);
          },
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildFilterHeader(dateLabel);
            }
            final row = filtered[index - 1];
            return _ReturnInspectionCard(
              row: row,
              dateFormat: widget.dateFormat,
              admin: widget.admin,
              showCompleteButton: false,
              showInspectionDate: true,
              onChanged: widget.onChanged,
            );
          },
        );
      },
    );
  }
}

class _InspectionFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _InspectionFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DanjiColors.buttonBlue : DanjiColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? DanjiColors.buttonBlue : DanjiColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? Colors.white : DanjiColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReturnInspectionListTab extends StatelessWidget {
  final Future<List<AdminReservationRow>>? future;
  final String emptyMessage;
  final DateFormat dateFormat;
  final AdminService admin;
  final bool showCompleteButton;
  final bool showInspectionDate;
  final Future<void> Function(AdminReservationRow row)? onComplete;
  final VoidCallback? onChanged;

  const _ReturnInspectionListTab({
    required this.future,
    required this.emptyMessage,
    required this.dateFormat,
    required this.admin,
    required this.showCompleteButton,
    this.showInspectionDate = false,
    this.onComplete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminReservationRow>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text(friendlyAdminError(snap.error!)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(child: Text(emptyMessage));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final row = list[index];
            return _ReturnInspectionCard(
              row: row,
              dateFormat: dateFormat,
              admin: admin,
              showCompleteButton: showCompleteButton,
              showInspectionDate: showInspectionDate,
              onComplete: showCompleteButton && onComplete != null
                  ? () => onComplete!(row)
                  : null,
              onChanged: onChanged,
            );
          },
        );
      },
    );
  }
}

class _DeductibleSection extends StatelessWidget {
  final AdminReservationRow row;
  final bool processing;
  final VoidCallback onCharge;
  final VoidCallback onWaive;

  const _DeductibleSection({
    required this.row,
    required this.processing,
    required this.onCharge,
    required this.onWaive,
  });

  static final _won = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final amount = row.deductibleAmount > 0
        ? row.deductibleAmount
        : AdminReservationRow.defaultDeductibleAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        const Text(
          '면책금',
          style: TextStyle(
            color: DanjiColors.accentRed,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        if (row.deductibleCharged) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: DanjiColors.buttonBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DanjiColors.buttonBlue.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: DanjiColors.buttonBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  '청구완료 ₩${_won.format(row.deductibleAmount > 0 ? row.deductibleAmount : amount)}',
                  style: const TextStyle(
                    color: DanjiColors.buttonBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ] else if (row.deductibleWaived) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: DanjiColors.textMuted.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DanjiColors.border),
            ),
            child: const Text(
              '면제',
              style: TextStyle(
                color: DanjiColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: processing ? null : onWaive,
                  child: const Text('면제'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: processing ? null : onCharge,
                  style: DanjiTheme.dangerButton,
                  child: processing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('₩${_won.format(amount)} 청구'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 검수 대기/완료 공통 — 불투명 사진 비교 영역 (로딩 중에도 플레이스홀더 표시)
class _ReturnInspectionPhotoSection extends StatelessWidget {
  final Future<({List<String> before, List<String> after})> future;

  const _ReturnInspectionPhotoSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<String> before, List<String> after})>(
      future: future,
      builder: (context, snap) {
        final photos = snap.data;
        return ReturnInspectionPhotoCompare(
          beforePhotos: photos?.before ?? const [],
          afterPhotos: photos?.after ?? const [],
        );
      },
    );
  }
}

class _ReturnInspectionCard extends StatefulWidget {
  final AdminReservationRow row;
  final DateFormat dateFormat;
  final VoidCallback? onComplete;
  final VoidCallback? onChanged;
  final AdminService admin;
  final bool showCompleteButton;
  final bool showInspectionDate;

  const _ReturnInspectionCard({
    required this.row,
    required this.dateFormat,
    required this.admin,
    this.onComplete,
    this.onChanged,
    this.showCompleteButton = true,
    this.showInspectionDate = false,
  });

  @override
  State<_ReturnInspectionCard> createState() => _ReturnInspectionCardState();
}

class _ReturnInspectionCardState extends State<_ReturnInspectionCard> {
  late Future<({List<String> before, List<String> after})> _photosFuture;
  bool _deductibleProcessing = false;

  @override
  void initState() {
    super.initState();
    _photosFuture = widget.admin.resolveInspectionPhotos(widget.row);
  }

  @override
  void didUpdateWidget(covariant _ReturnInspectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _photosFuture = widget.admin.resolveInspectionPhotos(widget.row);
    }
  }

  Future<void> _chargeDeductible() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('면책금 청구'),
        content: const Text(
          '고객 카드로 ₩500,000이 자동 결제됩니다. 진행하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('청구'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deductibleProcessing = true);
    try {
      await widget.admin.chargeReservationDeductible(widget.row.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('면책금이 청구되었습니다.')),
      );
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAdminError(e))),
      );
    } finally {
      if (mounted) setState(() => _deductibleProcessing = false);
    }
  }

  Future<void> _waiveDeductible() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('면책금 면제'),
        content: const Text('이 예약의 면책금을 면제 처리할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('면제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deductibleProcessing = true);
    try {
      await widget.admin.waiveReservationDeductible(widget.row.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('면책금이 면제되었습니다.')),
      );
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAdminError(e))),
      );
    } finally {
      if (mounted) setState(() => _deductibleProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  r.vehicleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (r.hasSecondDriver) const AdminSecondDriverBadge(),
              if (r.isNoShowReturn) const _NoShowReturnBadge(),
              if (r.isAccident) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DanjiColors.accentRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: DanjiColors.accentRed.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Text(
                    '사고',
                    style: TextStyle(
                      color: DanjiColors.accentRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${r.startAt != null ? widget.dateFormat.format(r.startAt!) : '-'} ~ '
            '${r.endAt != null ? widget.dateFormat.format(r.endAt!) : '-'}',
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
          if (widget.showInspectionDate) ...[
            const SizedBox(height: 6),
            Text(
              '검수 완료: ${r.updatedAt != null ? widget.dateFormat.format(r.updatedAt!) : '-'}',
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '예약번호: ${r.reservationNumberLabel}',
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '임차인: ${r.renterDisplayName}',
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
          AdminSecondDriverSummary(
            secondDriverName: r.secondDriverName,
            secondDriverLicense: r.secondDriverLicense,
          ),
          const SizedBox(height: 10),
          AdminReservationContractButton(
            admin: widget.admin,
            reservationId: r.id,
            contractContent: r.contractContent,
            vehicleName: r.vehicleName,
            renterName: r.renterDisplayName,
            secondDriverName: r.secondDriverName,
            secondDriverLicense: r.secondDriverLicense,
          ),
          if (r.isAccident) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DanjiColors.accentRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: DanjiColors.accentRed.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '사고 내용',
                    style: TextStyle(
                      color: DanjiColors.accentRed,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.accidentNote?.trim().isNotEmpty == true
                        ? r.accidentNote!.trim()
                        : '사고 메모가 없습니다.',
                    style: const TextStyle(
                      color: DanjiColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DeductibleSection(
                    row: r,
                    processing: _deductibleProcessing,
                    onCharge: _chargeDeductible,
                    onWaive: _waiveDeductible,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _ReturnInspectionPhotoSection(future: _photosFuture),
          if (widget.showCompleteButton) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.onComplete,
              style: r.isAccident
                  ? DanjiTheme.dangerButton
                  : DanjiTheme.primaryButton,
              child: Text(
                r.isAccident ? '사고 확인 후 검수 완료' : '검수 완료',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminSalesScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminSalesScreen({super.key, required this.profile});

  @override
  State<AdminSalesScreen> createState() => _AdminSalesScreenState();
}

class _AdminSalesScreenState extends State<AdminSalesScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  final _monthHeaderFormat = DateFormat('yyyy년 M월');
  late DateTime _selectedMonth;
  Future<SalesSummary>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _reload();
  }

  bool get _canGoNextMonth {
    final now = DateTime.now();
    return _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year &&
            _selectedMonth.month < now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
      _future = _fetchSummary();
    });
  }

  Future<SalesSummary> _fetchSummary() {
    return _admin.fetchSalesSummary(
      widget.profile.complexId,
      year: _selectedMonth.year,
      month: _selectedMonth.month,
    );
  }

  void _reload() {
    setState(() {
      _future = _fetchSummary();
    });
  }

  Widget _settlementRow(
    String label,
    int amount, {
    bool emphasize = false,
    bool isDeduction = false,
  }) {
    final prefix = isDeduction && amount > 0 ? '-' : '';
    final textStyle = TextStyle(
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      fontSize: emphasize ? 16 : 14,
      color: emphasize
          ? DanjiColors.buttonBlue
          : (isDeduction ? DanjiColors.textSecondary : DanjiColors.textPrimary),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyle)),
          Text(
            '$prefix₩${_won.format(amount)}',
            style: textStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementSection(SalesSummary summary) {
    final gross = summary.totalAmount;
    final vat = (gross * 0.10).round();
    final corporateTax = (gross * 0.033).round();
    final fee = summary.vehicleCount * 100000;
    final net = gross - vat - corporateTax - fee;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '정산 계산',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          _settlementRow('총매출', gross),
          const Divider(height: 16),
          _settlementRow('부가세 (10%)', vat, isDeduction: true),
          _settlementRow('법인세 (3.3%)', corporateTax, isDeduction: true),
          _settlementRow(
            '수수료 (차량 ${summary.vehicleCount}대 × ₩100,000)',
            fee,
            isDeduction: true,
          ),
          const Divider(height: 16),
          _settlementRow('최종 정산금', net, emphasize: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = _monthHeaderFormat.format(_selectedMonth);

    return AdminScaffold(
      appBar: const DanjiAppBar(title: '매출 관리'),
      body: FutureBuilder<SalesSummary>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snap.data ??
              const SalesSummary(totalAmount: 0, reservationCount: 0, rows: []);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              MonthFilterBar(
                label: monthLabel,
                canGoNext: _canGoNextMonth,
                onPrevious: () => _shiftMonth(-1),
                onNext: _canGoNextMonth ? () => _shiftMonth(1) : null,
              ),
              const SizedBox(height: 16),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$monthLabel 등록 차량 매출',
                      style: const TextStyle(color: DanjiColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₩${_won.format(summary.totalAmount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        color: DanjiColors.buttonBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('예약 ${summary.reservationCount}건'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSettlementSection(summary),
              const SizedBox(height: 16),
              const Text(
                '차량별 매출',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (summary.rows.isEmpty)
                SectionCard(child: Text('$monthLabel 매출 데이터가 없습니다.'))
              else
                ...summary.rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SectionCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          row.vehicleName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${row.count}건'),
                        trailing: Text(
                          '₩${_won.format(row.amount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: DanjiColors.buttonBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
