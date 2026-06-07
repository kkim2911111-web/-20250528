import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/danji_colors.dart';
import '../../widgets/section_card.dart';

class SuperAdminPeriodFilter extends StatelessWidget {
  final int year;
  final int month;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;

  const SuperAdminPeriodFilter({
    super.key,
    required this.year,
    required this.month,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final years = List.generate(5, (i) => DateTime.now().year - 2 + i);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: year,
            decoration: const InputDecoration(
              labelText: '연도',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text('$y년')))
                .toList(),
            onChanged: (v) {
              if (v != null) onYearChanged(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: month,
            decoration: const InputDecoration(
              labelText: '월',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              12,
              (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}월')),
            ),
            onChanged: (v) {
              if (v != null) onMonthChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class SuperAdminStatGrid extends StatelessWidget {
  final List<({String label, String value, Color color})> items;

  const SuperAdminStatGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (e) => SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48) / 2,
              child: SectionCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DanjiColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: e.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class SuperAdminChip extends StatelessWidget {
  final String label;
  final Color color;

  const SuperAdminChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

final superAdminWon = NumberFormat('#,###');
final superAdminDateTime = DateFormat('yyyy-MM-dd HH:mm');
