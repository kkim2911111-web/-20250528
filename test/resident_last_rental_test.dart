import 'package:flutter_test/flutter_test.dart';

/// get_admin_customers / get_super_admin_residents 최근대여 집계 미러
DateTime? latestCompletedReturnAt(
  List<Map<String, dynamic>> events,
) {
  DateTime? latest;
  for (final event in events) {
    if (event['status'] != 'completed') continue;
    final at = event['return_completed_at'] as DateTime?;
    if (at == null) continue;
    if (latest == null || at.isAfter(latest)) {
      latest = at;
    }
  }
  return latest;
}

void main() {
  test('취소 예약은 최근대여에서 제외, completed 반납완료일만 반영', () {
    final latest = latestCompletedReturnAt([
      {
        'status': 'cancelled',
        'return_completed_at': DateTime(2026, 5, 30),
      },
      {
        'status': 'confirmed',
        'return_completed_at': DateTime(2026, 5, 29),
      },
      {
        'status': 'completed',
        'return_completed_at': DateTime(2026, 5, 10),
      },
      {
        'status': 'completed',
        'return_completed_at': DateTime(2026, 5, 25, 14),
      },
    ]);

    expect(latest, DateTime(2026, 5, 25, 14));
  });
}
