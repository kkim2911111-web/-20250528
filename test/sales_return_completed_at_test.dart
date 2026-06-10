import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/sales_return_completed_at.dart';

void main() {
  group('resolveSalesReturnCompletedAt', () {
    test('returned_at 우선', () {
      final returned = DateTime(2026, 6, 15, 10);
      final actual = DateTime(2026, 6, 15, 11);

      expect(
        resolveSalesReturnCompletedAt(
          returnedAt: returned,
          actualEndAt: actual,
        ),
        returned,
      );
    });

    test('노쇼는 updated_at 폴백', () {
      final updated = DateTime(2026, 6, 20, 9);

      expect(
        resolveSalesReturnCompletedAt(
          isNoShow: true,
          updatedAt: updated,
        ),
        updated,
      );
    });
  });

  group('formatSalesRecognitionMonth', () {
    test('completed 반납완료일 기준 월', () {
      expect(
        formatSalesRecognitionMonth(DateTime.utc(2026, 5, 31, 15)),
        '2026년 6월',
      );
    });
  });
}
