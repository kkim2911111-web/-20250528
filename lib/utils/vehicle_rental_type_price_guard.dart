import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import 'rental_pricing.dart';

enum VehicleRentalTypeSaveGuardChoice {
  cancel,
  saveWithTogglesOff,
}

/// 대여 유형 ON + 요금 미입력 저장 가드
abstract final class VehicleRentalTypePriceGuard {
  static String messageFor(RentalType type) {
    switch (type) {
      case RentalType.hourly:
        return '시간렌트가 켜져 있지만 시간당 요금이 입력되지 않았습니다';
      case RentalType.daily:
        return '일렌트가 켜져 있지만 1일 요금이 입력되지 않았습니다';
      case RentalType.monthly:
        return '월렌트가 켜져 있지만 월 요금이 입력되지 않았습니다';
    }
  }

  static List<RentalType> findTypesMissingPrice({
    required Set<RentalType> types,
    required int hourlyPrice,
    required String dailyPriceText,
    required String monthlyPriceText,
  }) {
    final missing = <RentalType>[];
    if (types.contains(RentalType.hourly) && hourlyPrice <= 0) {
      missing.add(RentalType.hourly);
    }
    final dailyParsed = int.tryParse(dailyPriceText.trim());
    if (types.contains(RentalType.daily) &&
        (dailyPriceText.trim().isEmpty || dailyParsed == null || dailyParsed <= 0)) {
      missing.add(RentalType.daily);
    }
    final monthlyParsed = int.tryParse(monthlyPriceText.trim());
    if (types.contains(RentalType.monthly) &&
        (monthlyPriceText.trim().isEmpty ||
            monthlyParsed == null ||
            monthlyParsed <= 0)) {
      missing.add(RentalType.monthly);
    }
    return missing;
  }

  static Future<VehicleRentalTypeSaveGuardChoice?> showSaveGuardDialog(
    BuildContext context,
    List<RentalType> missingTypes,
  ) async {
    if (missingTypes.isEmpty) return VehicleRentalTypeSaveGuardChoice.saveWithTogglesOff;

    final body = missingTypes.map(messageFor).join('\n');
    return showDialog<VehicleRentalTypeSaveGuardChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('요금 입력 확인'),
        content: Text(
          '$body\n\n토글을 끄고 저장하시겠습니까?',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, VehicleRentalTypeSaveGuardChoice.cancel),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              VehicleRentalTypeSaveGuardChoice.saveWithTogglesOff,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.buttonBlue,
            ),
            child: const Text('토글 끄고 저장'),
          ),
        ],
      ),
    );
  }
}
