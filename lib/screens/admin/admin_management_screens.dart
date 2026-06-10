import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/inspection_photo.dart';
import '../../models/staff_profile.dart';
import '../../models/super_admin_models.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/admin_reservation_card_extras.dart';
import '../../widgets/return_inspection_photo_compare.dart';
import '../../widgets/section_card.dart';
import '../../widgets/settlement_detail_sheet.dart';
import '../../utils/reservation_display.dart';
import '../../widgets/rental_type_badge.dart';
import '../../widgets/reservation_times_panel.dart';
import '../../utils/vehicle_exposure_status.dart';
import '../../utils/vehicle_insurance_status.dart';
import 'admin_vehicle_detail_screen.dart';
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

  Future<void> _togglePublished(AdminVehicleDetail vehicle, bool on) async {
    if (on) {
      final confirmed = await _confirmPublishOn();
      if (!confirmed) return;
    }

    try {
      await _admin.setVehiclePublished(
        vehicleId: vehicle.id,
        published: on,
      );
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<void> _toggleMaintenance(AdminVehicleDetail vehicle, bool on) async {
    if (on) {
      final confirmed = await _confirmMaintenanceOn();
      if (!confirmed) return;

      final memo = await _showMaintenanceMemoDialog(
        initial: vehicle.maintenanceMemo,
      );
      if (memo == null || memo.trim().isEmpty) return;
      try {
        await _admin.setVehicleMaintenance(
          vehicleId: vehicle.id,
          underMaintenance: true,
          memo: memo.trim(),
        );
        _reload();
      } catch (e) {
        if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
      }
      return;
    }

    try {
      await _admin.setVehicleMaintenance(
        vehicleId: vehicle.id,
        underMaintenance: false,
      );
      _reload();
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
              return _AdminVehicleManageCard(
                vehicle: v,
                complexLabel: _vehicleComplexLabel(v, widget.profile),
                priceLabel: '₩${_won.format(v.pricePerHour)}/h',
                onOpenDetail: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => AdminVehicleDetailScreen(
                        profile: widget.profile,
                        vehicle: v,
                      ),
                    ),
                  );
                  if (ok == true) _reload();
                },
                onPublishedChanged: (value) => _togglePublished(v, value),
                onMaintenanceChanged: (value) => _toggleMaintenance(v, value),
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminVehicleManageCard extends StatelessWidget {
  final AdminVehicleDetail vehicle;
  final String complexLabel;
  final String priceLabel;
  final VoidCallback onOpenDetail;
  final ValueChanged<bool> onPublishedChanged;
  final ValueChanged<bool> onMaintenanceChanged;

  const _AdminVehicleManageCard({
    required this.vehicle,
    required this.complexLabel,
    required this.priceLabel,
    required this.onOpenDetail,
    required this.onPublishedChanged,
    required this.onMaintenanceChanged,
  });

  static const _maintenanceAccent = Color(0xFFF97316);
  static const _maintenanceBg = Color(0xFFFFF7ED);
  static const _maintenanceFooterBg = Color(0xFFF9FAFB);
  static const _publishFooterBg = Color(0xFFF3F4F6);

  @override
  Widget build(BuildContext context) {
    final exposure = vehicle.exposureStatus;
    final underMaintenance = vehicle.isUnderMaintenance;
    final memo = vehicle.maintenanceMemo?.trim();
    final hasMemo = memo != null && memo.isNotEmpty;
    final accentColor = VehicleExposureStatusUtil.color(exposure);
    final showAccentBar = exposure == VehicleExposureStatus.maintenance ||
        exposure == VehicleExposureStatus.insuranceExpired;

    return Container(
      decoration: BoxDecoration(
        color: SectionCard.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: exposure == VehicleExposureStatus.published
              ? DanjiColors.border
              : accentColor.withValues(alpha: 0.55),
          width: exposure == VehicleExposureStatus.published ? 1 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showAccentBar)
              ColoredBox(
                color: accentColor,
                child: const SizedBox(width: 4),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onOpenDetail,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          vehicle.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      VehicleExposureBadge(
                                        isPublished: vehicle.isPublished,
                                        isUnderMaintenance:
                                            vehicle.isUnderMaintenance,
                                        insuranceExpiresAt:
                                            vehicle.insuranceExpiresAt,
                                      ),
                                      if (VehicleInsuranceStatus.badgeKind(
                                            vehicle.insuranceExpiresAt,
                                          ) !=
                                          VehicleInsuranceBadgeKind.none) ...[
                                        const SizedBox(width: 6),
                                        VehicleInsuranceBadge(
                                          insuranceExpiresAt:
                                              vehicle.insuranceExpiresAt,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$complexLabel · ${vehicle.vehicleType} · '
                                    '${vehicle.fuelType ?? '-'} · $priceLabel',
                                    style: const TextStyle(
                                      color: DanjiColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${vehicle.carNumber ?? '번호 미등록'} · '
                                    '${vehicle.parkingLocation ?? '주차 미등록'}',
                                    style: const TextStyle(
                                      color: DanjiColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right,
                              color: DanjiColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ColoredBox(
                    color: vehicle.isPublished
                        ? _publishFooterBg
                        : const Color(0xFFEFF1F3),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle.isPublished
                                      ? '노출중 — 입주민 예약 목록에 표시'
                                      : '대기 — 입주민에게 미노출',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: vehicle.isPublished
                                        ? VehicleExposureStatusUtil
                                            .publishedColor
                                        : VehicleExposureStatusUtil.waitingColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vehicle.isPublished
                                      ? '끄면 대기 상태로 전환됩니다'
                                      : '켜면 입주민에게 노출됩니다',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DanjiColors.textMuted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: vehicle.isPublished,
                            activeThumbColor:
                                VehicleExposureStatusUtil.publishedColor,
                            onChanged: onPublishedChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ColoredBox(
                    color: underMaintenance
                        ? _maintenanceBg
                        : _maintenanceFooterBg,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  underMaintenance
                                      ? '점검중 — 입주민 예약 차단됨'
                                      : '점검중 설정',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: underMaintenance
                                        ? const Color(0xFFEA580C)
                                        : DanjiColors.textPrimary,
                                  ),
                                ),
                                if (underMaintenance && hasMemo) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    memo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: DanjiColors.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ] else if (!underMaintenance) ...[
                                  const SizedBox(height: 2),
                                  const Text(
                                    '켜면 입주민 예약이 차단됩니다',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DanjiColors.textMuted,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Switch(
                            value: underMaintenance,
                            activeThumbColor: _maintenanceAccent,
                            onChanged: onMaintenanceChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              final missing = !v.hasInsurance;
              final insuranceKind =
                  VehicleInsuranceStatus.badgeKind(v.insuranceExpiresAt);
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          v.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (!missing)
                        VehicleInsuranceBadge(
                          insuranceExpiresAt: v.insuranceExpiresAt,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    missing
                        ? '${_vehicleComplexLabel(v, widget.profile)} · 보험 미등록'
                        : '${_vehicleComplexLabel(v, widget.profile)}\n'
                            '${v.insuranceCompany}\n'
                            '증권 ${v.insurancePolicyNumber}\n'
                            '만료 ${v.insuranceExpiresAt != null ? _date.format(v.insuranceExpiresAt!) : '-'}',
                  ),
                  trailing: missing
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DanjiColors.accentRed.withValues(alpha: 0.12),
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
                        )
                      : insuranceKind == VehicleInsuranceBadgeKind.none
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF43A047)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                '정상',
                                style: TextStyle(
                                  color: Color(0xFF43A047),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : null,
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
          isPublished: vehicle.isPublished,
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

class _ReturnInspectionNoShowNotice extends StatelessWidget {
  const _ReturnInspectionNoShowNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        '예약 후 대여하지 않은 건(노쇼)은 검수 대상이 아닙니다.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFF44336),
          fontSize: 12,
          height: 1.4,
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
              '노쇼',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FutureBuilder<List<AdminReservationRow>>(
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ReturnInspectionNoShowNotice(),
        Expanded(
          child: FutureBuilder<List<AdminReservationRow>>(
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
          ),
        ),
      ],
    );
  }
}

class _DeductibleSection extends StatelessWidget {
  final AdminReservationRow row;
  final bool processing;
  final bool actionsEnabled;
  final VoidCallback onCharge;
  final VoidCallback onWaive;

  const _DeductibleSection({
    required this.row,
    required this.processing,
    this.actionsEnabled = true,
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
        ] else if (row.deductibleUnpaid) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: DanjiColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DanjiColors.danger.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '미수금 ₩${_won.format(row.deductibleAmount > 0 ? row.deductibleAmount : amount)}',
                  style: const TextStyle(
                    color: DanjiColors.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '자동 결제 재시도 실패 — 수동 결제 처리가 필요합니다.',
                  style: TextStyle(
                    color: DanjiColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      !actionsEnabled || processing ? null : onWaive,
                  child: const Text('면제'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed:
                      !actionsEnabled || processing ? null : onCharge,
                  style: DanjiTheme.dangerButton,
                  child: processing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('수동 청구'),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      !actionsEnabled || processing ? null : onWaive,
                  child: const Text('면제'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed:
                      !actionsEnabled || processing ? null : onCharge,
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
  final Future<InspectionPhotoSet> future;

  const _ReturnInspectionPhotoSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InspectionPhotoSet>(
      future: future,
      builder: (context, snap) {
        final photos = snap.data ?? InspectionPhotoSet.empty;
        return ReturnInspectionPhotoCompare(
          beforePhotos: photos.before,
          afterPhotos: photos.after,
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
  late Future<InspectionPhotoSet> _photosFuture;
  bool _deductibleProcessing = false;

  @override
  void initState() {
    super.initState();
    _photosFuture = widget.admin.resolveInspectionPhotoSet(widget.row);
  }

  @override
  void didUpdateWidget(covariant _ReturnInspectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _photosFuture = widget.admin.resolveInspectionPhotoSet(widget.row);
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
              RentalTypeBadge(rentalType: r.rentalType),
              if (r.isNoShow) const _NoShowReturnBadge(),
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
          ReservationTimesPanel(
            formatter: widget.dateFormat,
            mode: widget.showInspectionDate
                ? ReservationTimesMode.inspectionCompleted
                : ReservationTimesMode.inspectionPending,
            scheduledStartAt: r.startAt,
            scheduledEndAt: r.endAt,
            rentalStartedAt: r.rentalStartedAt,
            returnedAt: r.returnedAt,
            returnCompletedAt: r.returnCompletedAt,
            isNoShow: r.isNoShow,
          ),
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
            rentalPeriodOverride: formatRentalPeriod(
              formatter: widget.dateFormat,
              start: r.displayRentalStartAt,
              end: r.displayRentalEndAt,
            ),
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
                    actionsEnabled: !r.isNoShow,
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

  Future<void> _openSettlementDetail(
    SalesSummary summary, {
    SettlementDetailTab initialTab = SettlementDetailTab.rental,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: _AdminSettlementDetailSheet(
            admin: _admin,
            profile: widget.profile,
            year: _selectedMonth.year,
            month: _selectedMonth.month,
            summary: summary,
            initialTab: initialTab,
            onUpdated: () {
              Navigator.pop(ctx);
              _reload();
            },
          ),
        );
      },
    );
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
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -180 && _canGoNextMonth) {
                    _shiftMonth(1);
                  } else if (velocity > 180) {
                    _shiftMonth(-1);
                  }
                },
                child: MonthFilterBar(
                  label: monthLabel,
                  canGoNext: _canGoNextMonth,
                  onPrevious: () => _shiftMonth(-1),
                  onNext: _canGoNextMonth ? () => _shiftMonth(1) : null,
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$monthLabel 반납 완료 매출',
                            style: const TextStyle(
                              color: DanjiColors.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: settlementBadgeColor(
                              isSettled: summary.isSettled,
                              isRequested: summary.isRequested,
                              settledColor: const Color(0xFFDCFCE7),
                              requestedColor: const Color(0xFFFEF3C7),
                              unsettledColor: const Color(0xFFFEE2E2),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            summary.settlementBadgeLabel,
                            style: TextStyle(
                              color: settlementBadgeColor(
                                isSettled: summary.isSettled,
                                isRequested: summary.isRequested,
                                settledColor: const Color(0xFF16A34A),
                                requestedColor: const Color(0xFFD97706),
                                unsettledColor: DanjiColors.danger,
                              ),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'completed · 반납 완료일 기준',
                      style: TextStyle(
                        color: DanjiColors.textMuted,
                        fontSize: 12,
                      ),
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
                    const SizedBox(height: 12),
                    SettlementCountRow(
                      paymentCount: summary.paymentCount,
                      cancelCount: summary.cancelCount,
                      rentalCount: summary.rentalCount,
                      selectedTab: SettlementDetailTab.rental,
                      onTabSelected: (tab) =>
                          _openSettlementDetail(summary, initialTab: tab),
                    ),
                    if (summary.extensionRevenue > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '연장 매출 ₩${_won.format(summary.extensionRevenue)} 포함',
                        style: const TextStyle(
                          color: DanjiColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _openSettlementDetail(summary),
                      child: const Text('정산 상세 보기'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSettlementSection(summary),
              const SizedBox(height: 16),
              const Text(
                '차량별 가동률/수익률',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                '반납 완료 기준 · 가동률 = 실대여시간 합계 ÷ 744시간',
                style: TextStyle(
                  color: DanjiColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              if (summary.utilizationRows.isEmpty)
                SectionCard(
                  child: Text('$monthLabel 등록 차량이 없습니다.'),
                )
              else
                ...summary.utilizationRows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _VehicleUtilizationCard(
                      row: row,
                      won: _won,
                    ),
                  ),
                ),
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

class _VehicleUtilizationCard extends StatelessWidget {
  final VehicleUtilizationRow row;
  final NumberFormat won;

  const _VehicleUtilizationCard({
    required this.row,
    required this.won,
  });

  @override
  Widget build(BuildContext context) {
    final carNumber = row.carNumber?.trim();
    final utilizationLabel = row.utilizationPercent == row.utilizationPercent.roundToDouble()
        ? '${row.utilizationPercent.round()}%'
        : '${row.utilizationPercent.toStringAsFixed(1)}%';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.vehicleName,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: DanjiColors.textPrimary,
            ),
          ),
          if (carNumber != null && carNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              carNumber,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VehicleUtilizationMetric(
                  label: '대여 횟수',
                  value: '${row.rentalCount}회',
                ),
              ),
              Expanded(
                child: _VehicleUtilizationMetric(
                  label: '매출',
                  value: '₩${won.format(row.revenue)}',
                  emphasize: true,
                ),
              ),
              Expanded(
                child: _VehicleUtilizationMetric(
                  label: '가동률',
                  value: utilizationLabel,
                  emphasize: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VehicleUtilizationMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _VehicleUtilizationMetric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: DanjiColors.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            fontSize: emphasize ? 15 : 14,
            color: emphasize ? DanjiColors.buttonBlue : DanjiColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _AdminSettlementDetailSheet extends StatefulWidget {
  final AdminService admin;
  final StaffProfile profile;
  final int year;
  final int month;
  final SalesSummary summary;
  final SettlementDetailTab initialTab;
  final VoidCallback onUpdated;

  const _AdminSettlementDetailSheet({
    required this.admin,
    required this.profile,
    required this.year,
    required this.month,
    required this.summary,
    this.initialTab = SettlementDetailTab.rental,
    required this.onUpdated,
  });

  @override
  State<_AdminSettlementDetailSheet> createState() =>
      _AdminSettlementDetailSheetState();
}

class _AdminSettlementDetailSheetState extends State<_AdminSettlementDetailSheet> {
  late Future<SuperAdminSettlementSheet> _sheetFuture;
  bool _requesting = false;
  late SettlementDetailTab _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _reloadSheet();
  }

  void _reloadSheet() {
    setState(() {
      _sheetFuture = widget.admin.fetchSettlementSheet(
        year: widget.year,
        month: widget.month,
      );
    });
  }

  Future<void> _requestSettlement() async {
    setState(() => _requesting = true);
    try {
      await widget.admin.requestSettlement(
        year: widget.year,
        month: widget.month,
      );
      if (mounted) {
        DanjiSnackBar.show(context, '정산 요청이 전달되었습니다.');
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) {
        DanjiSnackBar.show(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.62;

    return SizedBox(
      height: sheetHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.profile.complexName ?? '단지',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<SuperAdminSettlementSheet>(
              future: _sheetFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(snap.error.toString()));
                }

                final sheet = snap.data ?? const SuperAdminSettlementSheet();
                final isSettled =
                    sheet.isSettled || widget.summary.isSettled;
                final isRequested =
                    sheet.isRequested || widget.summary.isRequested;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: settlementBadgeColor(
                            isSettled: isSettled,
                            isRequested: isRequested,
                            settledColor: const Color(0xFFDCFCE7),
                            requestedColor: const Color(0xFFFEF3C7),
                            unsettledColor: const Color(0xFFFEE2E2),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isSettled
                              ? '정산완료'
                              : (isRequested ? '정산요청' : '미정산'),
                          style: TextStyle(
                            color: settlementBadgeColor(
                              isSettled: isSettled,
                              isRequested: isRequested,
                              settledColor: const Color(0xFF16A34A),
                              requestedColor: const Color(0xFFD97706),
                              unsettledColor: DanjiColors.danger,
                            ),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SettlementCountRow(
                      paymentCount: sheet.paymentCount,
                      cancelCount: sheet.cancelCount,
                      rentalCount: sheet.rentalCount,
                      selectedTab: _selectedTab,
                      onTabSelected: (tab) => setState(() => _selectedTab = tab),
                    ),
                    const SizedBox(height: 12),
                    SettlementAmountRow(
                      label: '순 매출',
                      amount: sheet.netRevenue,
                      emphasize: true,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SettlementDetailList(
                        sheet: sheet,
                        tab: _selectedTab,
                        year: widget.year,
                        month: widget.month,
                      ),
                    ),
                    if (!isSettled && !isRequested) ...[
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _requesting ? null : _requestSettlement,
                        style: DanjiTheme.primaryButton,
                        child: _requesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('정산 요청'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
