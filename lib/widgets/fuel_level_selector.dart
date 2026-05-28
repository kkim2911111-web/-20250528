import 'package:flutter/material.dart';

import '../models/fuel_level.dart';

class FuelLevelSelector extends StatelessWidget {
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

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
            color: _textPrimary,
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
              selectedColor: const Color(0xFF4DA3FF),
              backgroundColor: const Color(0xFF132A3D),
              labelStyle: TextStyle(
                color: selected ? Colors.white : _textSecondary,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: selected
                    ? const Color(0xFF4DA3FF)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
