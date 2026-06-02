import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'admin_vehicle_form_screen.dart';

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
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
                        ? '보험 미등록'
                        : '${v.insuranceCompany}\n'
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
          name: vehicle.name,
          vehicleType: vehicle.vehicleType,
          fuelType: vehicle.fuelType,
          pricePerHour: price,
          parkingLocation: vehicle.parkingLocation,
          carNumber: vehicle.carNumber,
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
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
                  subtitle: Text('${v.vehicleType} · ${v.fuelType ?? '-'}'),
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
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
  Future<List<AdminReservationRow>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchReturnInspections(widget.profile.complexId);
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
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '반납 검수'),
      body: FutureBuilder<List<AdminReservationRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('검수 대기 중인 반납 차량이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = list[index];
              return SectionCard(
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
                      '${r.startAt != null ? _date.format(r.startAt!) : '-'} ~ '
                      '${r.endAt != null ? _date.format(r.endAt!) : '-'}',
                      style: const TextStyle(color: DanjiColors.textSecondary),
                    ),
                    if (r.isAccident)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '사고: ${r.accidentNote ?? '내용 없음'}',
                          style: const TextStyle(color: DanjiColors.accentRed),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _complete(r),
                      style: DanjiTheme.primaryButton,
                      child: const Text('검수 완료'),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
  Future<SalesSummary>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchSalesSummary(widget.profile.complexId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '이번 달 등록 차량 매출',
                      style: TextStyle(color: DanjiColors.textSecondary),
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
              const Text(
                '차량별 매출',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (summary.rows.isEmpty)
                const SectionCard(child: Text('매출 데이터가 없습니다.'))
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
