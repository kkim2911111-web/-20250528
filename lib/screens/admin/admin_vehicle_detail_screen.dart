import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../models/vehicle_maintenance.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/vehicle_exposure_status.dart';
import '../../utils/vehicle_insurance_status.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/admin_vehicle_location_section.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/rental_type_badge.dart';
import '../../widgets/section_card.dart';
import 'admin_vehicle_form_screen.dart';

class AdminVehicleDetailScreen extends StatefulWidget {
  final StaffProfile profile;
  final AdminVehicleDetail vehicle;

  const AdminVehicleDetailScreen({
    super.key,
    required this.profile,
    required this.vehicle,
  });

  @override
  State<AdminVehicleDetailScreen> createState() =>
      _AdminVehicleDetailScreenState();
}

class _AdminVehicleDetailScreenState extends State<AdminVehicleDetailScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  final _date = DateFormat('yyyy-MM-dd');
  final _time = DateFormat('yyyy-MM-dd HH:mm');
  late AdminVehicleDetail _vehicle;
  Future<List<VehicleMaintenanceRecord>>? _maintenanceFuture;
  Future<List<AdminReservationRow>>? _operatingFuture;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _vehicle = widget.vehicle;
    _reload();
  }

  void _reload() {
    setState(() {
      _maintenanceFuture = _admin.fetchVehicleMaintenanceHistory(_vehicle.id);
      _operatingFuture =
          _admin.fetchOperatingReservations(widget.profile.complexId);
    });
  }

  Future<void> _openEdit() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminVehicleFormScreen(
          profile: widget.profile,
          initial: _vehicle,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _refreshVehicle();
    }
  }

  Future<void> _refreshVehicle() async {
    final refreshed = await _admin.fetchVehicles(widget.profile.complexId);
    for (final v in refreshed) {
      if (v.id == _vehicle.id) {
        setState(() {
          _vehicle = v;
          _changed = true;
        });
        _reload();
        return;
      }
    }
  }

  Future<bool> _confirmPublishOn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('노출 전환'),
        content: const Text(
          '입주민에게 노출되어 예약을 받기 시작합니다. 노출할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('노출'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _confirmMaintenanceOn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('점검중 설정'),
        content: const Text(
          '점검중으로 설정하면 입주민 예약이 차단됩니다. 설정할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('설정'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _togglePublished(bool on) async {
    if (on) {
      final confirmed = await _confirmPublishOn();
      if (!confirmed) return;
    }

    try {
      await _admin.setVehiclePublished(
        vehicleId: _vehicle.id,
        published: on,
      );
      await _refreshVehicle();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<void> _toggleMaintenance(bool on) async {
    if (on) {
      final confirmed = await _confirmMaintenanceOn();
      if (!confirmed) return;

      final memo = await _showMaintenanceMemoDialog(
        initial: _vehicle.maintenanceMemo,
      );
      if (memo == null || memo.trim().isEmpty) return;
      try {
        await _admin.setVehicleMaintenance(
          vehicleId: _vehicle.id,
          underMaintenance: true,
          memo: memo.trim(),
        );
        await _refreshVehicle();
      } catch (e) {
        if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
      }
      return;
    }

    try {
      await _admin.setVehicleMaintenance(
        vehicleId: _vehicle.id,
        underMaintenance: false,
      );
      await _refreshVehicle();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<String?> _showMaintenanceMemoDialog({String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('점검 사유 입력'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '예: 엔진오일 교환, 타이어 점검',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _editPrice() async {
    final controller = TextEditingController(text: '${_vehicle.pricePerHour}');
    final price = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_vehicle.name} 가격'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '시간당 가격 (원)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
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
          id: _vehicle.id,
          complexId: _vehicle.complexId,
          complexName: _vehicle.complexName,
          name: _vehicle.name,
          vehicleType: _vehicle.vehicleType,
          fuelType: _vehicle.fuelType,
          pricePerHour: price,
          dailyPrice: _vehicle.dailyPrice,
          monthlyPrice: _vehicle.monthlyPrice,
          rentalTypes: _vehicle.rentalTypes,
          parkingLocation: _vehicle.parkingLocation,
          carNumber: _vehicle.carNumber,
          ownerName: _vehicle.ownerName,
          isPublished: _vehicle.isPublished,
          isAvailable: _vehicle.isAvailable,
          insuranceCompany: _vehicle.insuranceCompany,
          insurancePolicyNumber: _vehicle.insurancePolicyNumber,
          insuranceExpiresAt: _vehicle.insuranceExpiresAt,
          totalMileage: _vehicle.totalMileage,
          isUnderMaintenance: _vehicle.isUnderMaintenance,
          maintenanceMemo: _vehicle.maintenanceMemo,
        ),
      );
      await _refreshVehicle();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<void> _showAddMaintenanceDialog() async {
    VehicleMaintenanceType type = VehicleMaintenanceType.repair;
    final descController = TextEditingController();
    final costController = TextEditingController();
    final mileageController = TextEditingController(
      text: _vehicle.totalMileage > 0 ? '${_vehicle.totalMileage}' : '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('정비 등록'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<VehicleMaintenanceType>(
                  key: ValueKey(type),
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: '유형',
                    border: OutlineInputBorder(),
                  ),
                  items: VehicleMaintenanceType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Row(
                            children: [
                              Icon(t.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(t.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '비용 (원)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mileageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '주행거리 (km)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );

    final description = descController.text.trim();
    final cost = int.tryParse(costController.text.replaceAll(',', '')) ?? 0;
    final mileageText = mileageController.text.trim();
    final mileage = mileageText.isEmpty ? null : int.tryParse(mileageText);
    descController.dispose();
    costController.dispose();
    mileageController.dispose();

    if (saved != true) return;

    try {
      await _admin.insertVehicleMaintenance(
        vehicleId: _vehicle.id,
        type: type,
        description: description.isEmpty ? null : description,
        cost: cost,
        mileage: mileage,
      );
      if (!mounted) return;
      await _refreshVehicle();
      DanjiSnackBar.show(context, '정비 이력을 등록했습니다.');
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: AdminScaffold(
        appBar: DanjiAppBar(
          title: _vehicle.name,
          showHome: false,
          onBack: () => Navigator.pop(context, _changed),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: DanjiColors.buttonBlue,
          onPressed: _showAddMaintenanceDialog,
          icon: const Icon(Icons.build_outlined),
          label: const Text('정비 등록'),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _refreshVehicle();
          },
          child: FutureBuilder<List<AdminReservationRow>>(
            future: _operatingFuture,
            builder: (context, opSnap) {
              final operating = opSnap.data ?? const [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
                children: [
                  _SectionTitle('기본정보 · 상태'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoRow(label: '번호', value: _vehicle.carNumber ?? '미등록'),
                        _InfoRow(label: '차종', value: _vehicle.vehicleType),
                        _InfoRow(label: '연료', value: _vehicle.fuelType ?? '-'),
                        _InfoRow(
                          label: '주행거리',
                          value: '${_won.format(_vehicle.totalMileage)} km',
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 72,
                              child: Text(
                                '대여 유형',
                                style: TextStyle(
                                  color: DanjiColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            RentalTypeBadgeGroup(
                              rentalTypes: _vehicle.rentalTypes,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                              width: 72,
                              child: Text(
                                '노출 상태',
                                style: TextStyle(
                                  color: DanjiColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            VehicleExposureBadge(
                              isPublished: _vehicle.isPublished,
                              isUnderMaintenance: _vehicle.isUnderMaintenance,
                              insuranceExpiresAt: _vehicle.insuranceExpiresAt,
                            ),
                            if (VehicleInsuranceStatus.badgeKind(
                                  _vehicle.insuranceExpiresAt,
                                ) !=
                                VehicleInsuranceBadgeKind.none) ...[
                              const SizedBox(width: 8),
                              VehicleInsuranceBadge(
                                insuranceExpiresAt:
                                    _vehicle.insuranceExpiresAt,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('노출 설정'),
                          subtitle: Text(
                            _vehicle.isPublished
                                ? '입주민 예약 목록에 표시 중'
                                : '대기 — 입주민에게 미노출',
                          ),
                          value: _vehicle.isPublished,
                          activeThumbColor:
                              VehicleExposureStatusUtil.publishedColor,
                          onChanged: _togglePublished,
                        ),
                        if (_vehicle.isUnderMaintenance) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '점검중'
                              '${_vehicle.maintenanceMemo?.trim().isNotEmpty == true ? ': ${_vehicle.maintenanceMemo!.trim()}' : ''}',
                              style: const TextStyle(
                                color: Color(0xFFF97316),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('점검중 설정'),
                          subtitle: const Text('켜면 입주민 예약이 차단됩니다'),
                          value: _vehicle.isUnderMaintenance,
                          activeThumbColor: const Color(0xFFF97316),
                          onChanged: _toggleMaintenance,
                        ),
                        FilledButton.icon(
                          onPressed: _openEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('차량 정보 수정'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle('실시간 위치'),
                  AdminVehicleLocationSection(
                    vehicle: _vehicle,
                    operating: operating
                        .where(
                          (r) =>
                              r.vehicleName == _vehicle.name &&
                              (r.carNumber == null ||
                                  r.carNumber == _vehicle.carNumber),
                        )
                        .toList(),
                    timeFormat: _time,
                    compact: true,
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle('시간당 가격'),
                  SectionCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '시간당 요금',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '일 ${ _vehicle.dailyPrice != null ? '₩${_won.format(_vehicle.dailyPrice!)}' : '-'} · '
                        '월 ${_vehicle.monthlyPrice != null ? '₩${_won.format(_vehicle.monthlyPrice!)}' : '-'}',
                      ),
                      trailing: Text(
                        '₩${_won.format(_vehicle.pricePerHour)}/h',
                        style: const TextStyle(
                          color: DanjiColors.buttonBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      onTap: _editPrice,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle('보험'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _vehicle.hasInsurance
                                    ? (_vehicle.insuranceCompany ?? '보험사 미등록')
                                    : '보험 미등록',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (_vehicle.hasInsurance)
                              VehicleInsuranceBadge(
                                insuranceExpiresAt: _vehicle.insuranceExpiresAt,
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      DanjiColors.accentRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '미등록',
                                  style: TextStyle(
                                    color: DanjiColors.accentRed,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_vehicle.hasInsurance) ...[
                          const SizedBox(height: 8),
                          Text('증권 ${_vehicle.insurancePolicyNumber ?? '-'}'),
                          Text(
                            '만료 ${_vehicle.insuranceExpiresAt != null ? _date.format(_vehicle.insuranceExpiresAt!) : '-'}',
                          ),
                          if (VehicleInsuranceStatus.badgeKind(
                                _vehicle.insuranceExpiresAt,
                              ) ==
                              VehicleInsuranceBadgeKind.none)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                '보험 상태 정상',
                                style: TextStyle(
                                  color: Color(0xFF43A047),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openEdit,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Text(
                            _vehicle.hasInsurance ? '보험 정보 수정' : '보험 등록',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle('정비 이력'),
                  FutureBuilder<List<VehicleMaintenanceRecord>>(
                    future: _maintenanceFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SectionCard(
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final records = snap.data ?? [];
                      if (records.isEmpty) {
                        return const SectionCard(
                          child: Text('등록된 정비 이력이 없습니다.'),
                        );
                      }
                      return Column(
                        children: records.take(5).map((r) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(r.type.icon, color: DanjiColors.buttonBlue),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${r.type.label} · ${_date.format(r.performedAt)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (r.description?.trim().isNotEmpty ??
                                            false)
                                          Text(r.description!.trim()),
                                        Text(
                                          '₩${_won.format(r.cost)}'
                                          '${r.mileage != null ? ' · ${_won.format(r.mileage!)} km' : ''}',
                                          style: const TextStyle(
                                            color: DanjiColors.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
