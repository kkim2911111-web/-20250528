import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../utils/rental_pricing.dart';

class RentalTypeBadge extends StatelessWidget {
  final RentalType? rentalType;
  final String? rentalTypeDb;

  const RentalTypeBadge({
    super.key,
    this.rentalType,
    this.rentalTypeDb,
  });

  RentalType? get _type =>
      rentalType ?? RentalType.fromDb(rentalTypeDb);

  @override
  Widget build(BuildContext context) {
    final type = _type;
    if (type == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DanjiColors.buttonBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: DanjiColors.buttonBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        type.label,
        style: const TextStyle(
          color: DanjiColors.buttonBlue,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
