import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/danji_colors.dart';
import '../utils/rental_pricing.dart';

class VehicleRentalTypesSection extends StatefulWidget {
  final Set<RentalType> selectedTypes;
  final ValueChanged<Set<RentalType>> onTypesChanged;
  final TextEditingController hourlyPriceController;
  final TextEditingController dailyPriceController;
  final TextEditingController monthlyPriceController;

  const VehicleRentalTypesSection({
    super.key,
    required this.selectedTypes,
    required this.onTypesChanged,
    required this.hourlyPriceController,
    required this.dailyPriceController,
    required this.monthlyPriceController,
  });

  @override
  State<VehicleRentalTypesSection> createState() =>
      _VehicleRentalTypesSectionState();
}

class _VehicleRentalTypesSectionState extends State<VehicleRentalTypesSection> {
  static final _won = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    widget.hourlyPriceController.addListener(_rebuild);
    widget.dailyPriceController.addListener(_rebuild);
    widget.monthlyPriceController.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.hourlyPriceController.removeListener(_rebuild);
    widget.dailyPriceController.removeListener(_rebuild);
    widget.monthlyPriceController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  int get _hourlyPrice =>
      int.tryParse(widget.hourlyPriceController.text.trim()) ?? 0;

  int get _dailyInput =>
      int.tryParse(widget.dailyPriceController.text.trim()) ?? -1;

  int get _monthlyInput =>
      int.tryParse(widget.monthlyPriceController.text.trim()) ?? -1;

  int get _previewDaily =>
      _dailyInput >= 0 ? _dailyInput : RentalPricing.previewDailyPrice(_hourlyPrice);

  int get _previewMonthly {
    final dailyBase =
        _dailyInput >= 0 ? _dailyInput : RentalPricing.previewDailyPrice(_hourlyPrice);
    return _monthlyInput >= 0
        ? _monthlyInput
        : RentalPricing.previewMonthlyPrice(dailyBase);
  }

  void _toggleType(RentalType type, bool selected) {
    final next = Set<RentalType>.from(widget.selectedTypes);
    if (selected) {
      next.add(type);
    } else {
      if (next.length <= 1) return;
      next.remove(type);
    }
    widget.onTypesChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '대여 유형 설정',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '복수 선택 가능합니다. 선택한 유형만 입주민 예약 화면에 표시됩니다.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: RentalType.values.map((type) {
            final selected = widget.selectedTypes.contains(type);
            return FilterChip(
              label: Text(type.label),
              selected: selected,
              onSelected: (value) => _toggleType(type, value),
              selectedColor: DanjiColors.buttonBlue.withValues(alpha: 0.15),
              checkmarkColor: DanjiColors.buttonBlue,
              labelStyle: TextStyle(
                color: selected
                    ? DanjiColors.buttonBlue
                    : DanjiColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: selected
                    ? DanjiColors.buttonBlue
                    : Colors.grey.shade300,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (widget.selectedTypes.contains(RentalType.hourly)) ...[
          _priceField(
            label: '시간당 요금 (원)',
            controller: widget.hourlyPriceController,
            hint: '예: 5000',
          ),
          const SizedBox(height: 12),
        ],
        if (widget.selectedTypes.contains(RentalType.daily)) ...[
          _priceField(
            label: '1일 요금 (원)',
            controller: widget.dailyPriceController,
            hint: '미입력 시 시간당 × 20',
          ),
          if (widget.dailyPriceController.text.trim().isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '미리보기: ₩${_won.format(_previewDaily)} (시간당 × 20)',
              style: const TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        if (widget.selectedTypes.contains(RentalType.monthly)) ...[
          _priceField(
            label: '월 요금 (원)',
            controller: widget.monthlyPriceController,
            hint: '미입력 시 1일 요금 × 25',
          ),
          if (widget.monthlyPriceController.text.trim().isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '미리보기: ₩${_won.format(_previewMonthly)} (1일 요금 × 25)',
              style: const TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _priceField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
