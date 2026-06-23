import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:danjicar_app/utils/reservation_display.dart';

void main() {
  test('formatHistoryTimeRangeLabel — 동일일 HH:mm', () {
    final start = DateTime(2026, 6, 12, 17, 0);
    final end = DateTime(2026, 6, 12, 18, 0);
    expect(
      formatHistoryTimeRangeLabel(prefix: '예약', start: start, end: end),
      '예약 17:00 ~ 18:00',
    );
  });

  test('formatHistoryTimeRangeLabel — 실제 시각', () {
    final start = DateTime(2026, 6, 12, 16, 39);
    final end = DateTime(2026, 6, 12, 21, 59);
    expect(
      formatHistoryTimeRangeLabel(prefix: '실제', start: start, end: end),
      '실제 16:39 ~ 21:59',
    );
  });

  test('formatHistoryTimeRangeLabel — 다른 날 full formatter', () {
    final start = DateTime(2026, 6, 12, 22, 0);
    final end = DateTime(2026, 6, 13, 10, 0);
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    expect(
      formatHistoryTimeRangeLabel(
        prefix: '예약',
        start: start,
        end: end,
        fullFormatter: fmt,
      ),
      '예약 2026-06-12 22:00 ~ 2026-06-13 10:00',
    );
  });
}
