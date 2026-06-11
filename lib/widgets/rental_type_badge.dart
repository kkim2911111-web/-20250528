import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../utils/rental_pricing.dart';

class RentalTypeBadgeStyle {
  final String letter;
  final Color foreground;
  final Color background;
  final Color border;

  const RentalTypeBadgeStyle({
    required this.letter,
    required this.foreground,
    required this.background,
    required this.border,
  });
}

RentalTypeBadgeStyle rentalTypeBadgeStyle(RentalType type) {
  switch (type) {
    case RentalType.hourly:
      return RentalTypeBadgeStyle(
        letter: 'S',
        foreground: DanjiColors.buttonBlue,
        background: DanjiColors.buttonBlue.withValues(alpha: 0.12),
        border: DanjiColors.buttonBlue.withValues(alpha: 0.35),
      );
    case RentalType.daily:
      return const RentalTypeBadgeStyle(
        letter: 'R',
        foreground: Color(0xFF16A34A),
        background: Color(0xFFDCFCE7),
        border: Color(0xFF86EFAC),
      );
    case RentalType.monthly:
      return const RentalTypeBadgeStyle(
        letter: 'RR',
        foreground: Color(0xFF7C3AED),
        background: Color(0xFFEDE9FE),
        border: Color(0xFFC4B5FD),
      );
  }
}

const rentalTypeLegendText = 'S 카셰어링 · R 일반렌트 · RR 월렌트';

class RentalTypeBadge extends StatelessWidget {
  final RentalType? rentalType;
  final String? rentalTypeDb;

  const RentalTypeBadge({
    super.key,
    this.rentalType,
    this.rentalTypeDb,
  });

  RentalType? get _type => rentalType ?? RentalType.fromDb(rentalTypeDb);

  @override
  Widget build(BuildContext context) {
    final type = _type;
    if (type == null) return const SizedBox.shrink();
    return _RentalTypeChip(style: rentalTypeBadgeStyle(type));
  }
}

class RentalTypeBadgeGroup extends StatelessWidget {
  final List<RentalType>? rentalTypes;
  final dynamic rentalTypesDb;

  const RentalTypeBadgeGroup({
    super.key,
    this.rentalTypes,
    this.rentalTypesDb,
  });

  List<RentalType> get _types {
    final parsed = rentalTypes ??
        RentalPricing.parseRentalTypes(rentalTypesDb);
    const order = [RentalType.hourly, RentalType.daily, RentalType.monthly];
    return order.where(parsed.contains).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    if (types.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < types.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _RentalTypeChip(style: rentalTypeBadgeStyle(types[i])),
        ],
      ],
    );
  }
}

class RentalTypeBadgeLegend extends StatelessWidget {
  const RentalTypeBadgeLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: rentalTypeLegendText,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _RentalTypeChip(
                style: RentalTypeBadgeStyle(
                  letter: 'S',
                  foreground: DanjiColors.buttonBlue,
                  background: Color(0xFFE8F1FF),
                  border: Color(0xFF93C5FD),
                ),
              ),
              const SizedBox(width: 4),
              const _RentalTypeChip(
                style: RentalTypeBadgeStyle(
                  letter: 'R',
                  foreground: Color(0xFF16A34A),
                  background: Color(0xFFDCFCE7),
                  border: Color(0xFF86EFAC),
                ),
              ),
              const SizedBox(width: 4),
              const _RentalTypeChip(
                style: RentalTypeBadgeStyle(
                  letter: 'RR',
                  foreground: Color(0xFF7C3AED),
                  background: Color(0xFFEDE9FE),
                  border: Color(0xFFC4B5FD),
                ),
              ),
            ],
          ),
          const Text(
            rentalTypeLegendText,
            style: TextStyle(
              fontSize: 11,
              color: DanjiColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RentalTypeChip extends StatelessWidget {
  final RentalTypeBadgeStyle style;

  const _RentalTypeChip({required this.style});

  @override
  Widget build(BuildContext context) {
    final isWide = style.letter.length > 1;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 5 : 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: style.border),
      ),
      child: Text(
        style.letter,
        style: TextStyle(
          color: style.foreground,
          fontSize: isWide ? 10 : 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}
