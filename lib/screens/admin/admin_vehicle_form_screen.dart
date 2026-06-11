import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/rental_pricing.dart';
import '../../utils/vehicle_insurance_status.dart';
import '../../utils/vehicle_rental_type_price_guard.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/vehicle_rental_types_section.dart';

class AdminVehicleFormScreen extends StatefulWidget {
  final StaffProfile profile;
  final AdminVehicleDetail? initial;

  const AdminVehicleFormScreen({
    super.key,
    required this.profile,
    this.initial,
  });

  @override
  State<AdminVehicleFormScreen> createState() => _AdminVehicleFormScreenState();
}

class _AdminVehicleFormScreenState extends State<AdminVehicleFormScreen> {
  final _admin = AdminService();
  final _name = TextEditingController();
  final _ownerName = TextEditingController();
  final _carNumber = TextEditingController();
  final _hourlyPrice = TextEditingController();
  final _dailyPrice = TextEditingController();
  final _monthlyPrice = TextEditingController();
  final _monthlyExcessDailyPrice = TextEditingController();
  final _parking = TextEditingController();
  final _insuranceCompany = TextEditingController();
  final _insurancePolicy = TextEditingController();
  final _insuranceExpiry = TextEditingController();

  String _vehicleType = AdminService.vehicleTypes.first;
  String _fuelType = AdminService.fuelTypes.first;
  Set<RentalType> _rentalTypes = {RentalType.hourly};
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    if (v != null) {
      _name.text = v.name;
      _ownerName.text = v.ownerName ?? '';
      _carNumber.text = v.carNumber ?? '';
      _hourlyPrice.text = v.pricePerHour.toString();
      if (v.dailyPrice != null) _dailyPrice.text = v.dailyPrice.toString();
      if (v.monthlyPrice != null) {
        _monthlyPrice.text = v.monthlyPrice.toString();
      }
      if (v.monthlyExcessDailyPrice != null) {
        _monthlyExcessDailyPrice.text = v.monthlyExcessDailyPrice.toString();
      }
      _rentalTypes = v.rentalTypes.toSet();
      _parking.text = v.parkingLocation ?? '';
      _insuranceCompany.text = v.insuranceCompany ?? '';
      _insurancePolicy.text = v.insurancePolicyNumber ?? '';
      _insuranceExpiry.text = v.insuranceExpiresAt != null
          ? DateFormat('yyyy-MM-dd').format(v.insuranceExpiresAt!)
          : '';
      _vehicleType = v.vehicleType;
      _fuelType = v.fuelType ?? AdminService.fuelTypes.first;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ownerName.dispose();
    _carNumber.dispose();
    _hourlyPrice.dispose();
    _dailyPrice.dispose();
    _monthlyPrice.dispose();
    _monthlyExcessDailyPrice.dispose();
    _parking.dispose();
    _insuranceCompany.dispose();
    _insurancePolicy.dispose();
    _insuranceExpiry.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      _insuranceExpiry.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final hourlyPrice = int.tryParse(_hourlyPrice.text.trim()) ?? -1;
    final dailyText = _dailyPrice.text.trim();
    final monthlyText = _monthlyPrice.text.trim();
    final excessText = _monthlyExcessDailyPrice.text.trim();
    final dailyPrice = dailyText.isEmpty ? null : int.tryParse(dailyText);
    final monthlyPrice = monthlyText.isEmpty ? null : int.tryParse(monthlyText);
    final monthlyExcessDailyPrice =
        excessText.isEmpty ? null : int.tryParse(excessText);

    if (name.isEmpty) {
      setState(() => _error = '차종(모델명)을 입력해주세요.');
      return;
    }
    if (_rentalTypes.isEmpty) {
      setState(() => _error = '대여 유형을 1개 이상 선택해주세요.');
      return;
    }
    if (_rentalTypes.contains(RentalType.hourly) && hourlyPrice < 0) {
      setState(() => _error = '시간당 요금을 올바르게 입력해주세요.');
      return;
    }
    if (dailyPrice != null && dailyPrice < 0) {
      setState(() => _error = '1일 요금을 올바르게 입력해주세요.');
      return;
    }
    if (monthlyPrice != null && monthlyPrice < 0) {
      setState(() => _error = '월 요금을 올바르게 입력해주세요.');
      return;
    }
    if (monthlyExcessDailyPrice != null && monthlyExcessDailyPrice < 0) {
      setState(() => _error = '초과 일요금을 올바르게 입력해주세요.');
      return;
    }

    var rentalTypes = Set<RentalType>.from(_rentalTypes);
    final missingPrices = VehicleRentalTypePriceGuard.findTypesMissingPrice(
      types: rentalTypes,
      hourlyPrice: hourlyPrice,
      dailyPriceText: dailyText,
      monthlyPriceText: monthlyText,
    );
    if (missingPrices.isNotEmpty) {
      final choice = await VehicleRentalTypePriceGuard.showSaveGuardDialog(
        context,
        missingPrices,
      );
      if (choice != VehicleRentalTypeSaveGuardChoice.saveWithTogglesOff) {
        return;
      }
      rentalTypes.removeAll(missingPrices);
      if (rentalTypes.isEmpty) {
        setState(() => _error = '대여 유형을 1개 이상 선택해주세요.');
        return;
      }
      setState(() => _rentalTypes = rentalTypes);
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final expiry = DateTime.tryParse(_insuranceExpiry.text.trim());

    final vehicle = AdminVehicleDetail(
      id: widget.initial?.id ?? '',
      complexId: widget.profile.complexId,
      name: name,
      vehicleType: _vehicleType,
      fuelType: _fuelType,
      pricePerHour: rentalTypes.contains(RentalType.hourly) ? hourlyPrice : 0,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
      monthlyExcessDailyPrice: monthlyExcessDailyPrice,
      rentalTypes: rentalTypes.toList(),
      parkingLocation: _parking.text.trim().isEmpty ? null : _parking.text.trim(),
      ownerName: _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
      carNumber: _carNumber.text.trim().isEmpty ? null : _carNumber.text.trim(),
      isPublished: widget.initial?.isPublished ?? false,
      isAvailable: widget.initial?.isAvailable ?? true,
      insuranceCompany: _insuranceCompany.text.trim().isEmpty
          ? null
          : _insuranceCompany.text.trim(),
      insurancePolicyNumber: _insurancePolicy.text.trim().isEmpty
          ? null
          : _insurancePolicy.text.trim(),
      insuranceExpiresAt: expiry,
    );

    try {
      if (_isEdit) {
        await _admin.updateVehicle(vehicle);
      } else {
        await _admin.createVehicle(vehicle);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: DanjiAppBar(title: _isEdit ? '차량 수정' : '차량 등록'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_isEdit &&
              VehicleInsuranceStatus.badgeKind(
                    widget.initial?.insuranceExpiresAt,
                  ) !=
                  VehicleInsuranceBadgeKind.none) ...[
            VehicleInsuranceBadge(
              insuranceExpiresAt: widget.initial?.insuranceExpiresAt,
            ),
            const SizedBox(height: 16),
          ],
          _field('차종 / 모델명', _name, hint: '예: 더 뉴 스타리아'),
          const SizedBox(height: 12),
          _dropdown('차량 유형', _vehicleType, AdminService.vehicleTypes, (v) {
            setState(() => _vehicleType = v);
          }),
          const SizedBox(height: 12),
          _dropdown('유종', _fuelType, AdminService.fuelTypes, (v) {
            setState(() => _fuelType = v);
          }),
          const SizedBox(height: 12),
          _field('임대인(업체명)', _ownerName, hint: 'GT컴퍼니'),
          const SizedBox(height: 12),
          _field('차량번호', _carNumber, hint: '12가 3456'),
          const SizedBox(height: 12),
          _field('주차 위치', _parking, hint: 'B1-08'),
          const SizedBox(height: 20),
          const Text(
            '보험 정보',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          _field('보험사', _insuranceCompany, hint: '예: DB손해보험'),
          const SizedBox(height: 12),
          _field('증권번호', _insurancePolicy),
          const SizedBox(height: 12),
          TextField(
            controller: _insuranceExpiry,
            readOnly: true,
            onTap: _pickExpiry,
            decoration: _dec('만료일'),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 8),
            const Text(
              '등록 후 차량 상세에서 노출 전환할 수 있습니다. 신규 차량은 대기 상태로 등록됩니다.',
              style: TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 20),
          VehicleRentalTypesSection(
            selectedTypes: _rentalTypes,
            onTypesChanged: (types) => setState(() => _rentalTypes = types),
            hourlyPriceController: _hourlyPrice,
            dailyPriceController: _dailyPrice,
            monthlyPriceController: _monthlyPrice,
            monthlyExcessDailyPriceController: _monthlyExcessDailyPrice,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: DanjiColors.accentRed)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: DanjiTheme.primaryButton.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
            ),
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? '저장' : '등록'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      decoration: _dec(label, hint: hint),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _dec(label),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );
}
