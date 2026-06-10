import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/rental_detail.dart';

RentalDetailData _detail({
  required String status,
  bool isNoShow = false,
}) {
  return RentalDetailData(
    id: '1',
    vehicleName: '테스트',
    status: status,
    isNoShow: isNoShow,
    renterName: '홍길동',
    payment: const RentalPaymentInfo(totalPrice: 10000),
  );
}

void main() {
  group('하단 액션 노출', () {
    test('이용중 — 강제반납·결제취소', () {
      final d = _detail(status: 'in_use');
      expect(d.canShowForceReturnButton, isTrue);
      expect(d.canShowPaymentCancelButton, isTrue);
    });

    test('예약확정 — 결제취소만', () {
      final d = _detail(status: 'confirmed');
      expect(d.canShowForceReturnButton, isFalse);
      expect(d.canShowPaymentCancelButton, isTrue);
    });

    test('완료 — 액션 없음', () {
      final d = _detail(status: 'completed');
      expect(d.showForceActionButtons, isFalse);
    });

    test('노쇼 — 강제 액션 없음', () {
      final d = _detail(status: 'in_use', isNoShow: true);
      expect(d.showForceActionButtons, isFalse);
    });

    test('취소 — 액션 없음', () {
      final d = _detail(status: 'cancelled');
      expect(d.showForceActionButtons, isFalse);
    });
  });

  group('반납·검수 섹션', () {
    test('returned/completed만 표시', () {
      expect(_detail(status: 'returned').showReturnInspectionSection, isTrue);
      expect(_detail(status: 'completed').showReturnInspectionSection, isTrue);
      expect(_detail(status: 'in_use').showReturnInspectionSection, isFalse);
      expect(_detail(status: 'confirmed').showReturnInspectionSection, isFalse);
      expect(_detail(status: 'cancelled').showReturnInspectionSection, isFalse);
    });
  });
}
