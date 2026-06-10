import 'package:danjicar_app/widgets/settlement_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('매출 ₩0 단지는 정산 없음', () {
    expect(
      settlementStatusLabel(
        isSettled: false,
        isRequested: false,
        revenueAmount: 0,
        settledLabel: '완료',
      ),
      '정산 없음',
    );
  });
}
