import 'package:flutter/material.dart';

import '../models/fuel_level.dart';
import '../theme/danji_colors.dart';

class FuelLevelSelector extends StatelessWidget {
  final FuelLevel? value;
  final ValueChanged<FuelLevel> onChanged;

  const FuelLevelSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '주유 상태',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FuelLevel.values.map((level) {
            final selected = value == level;
            return ChoiceChip(
              label: Text(level.label),
              selected: selected,
              onSelected: (_) => onChanged(level),
              selectedColor: DanjiColors.rentalBlue,
              backgroundColor: DanjiColors.skyLight,
              labelStyle: TextStyle(
                color: selected ? Colors.white : DanjiColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: selected ? DanjiColors.rentalBlue : DanjiColors.border,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
