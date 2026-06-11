import 'package:danjicar_app/utils/time_remaining_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTimeRemaining boundary hours', () {
    expect(formatTimeRemaining(const Duration(hours: 23, minutes: 59)), '23시간 59분 남음');
    expect(formatTimeRemaining(const Duration(hours: 24)), '1일');
    expect(formatTimeRemaining(const Duration(hours: 25)), '1일 1시간');
    expect(formatTimeRemaining(const Duration(hours: 47)), '1일 23시간');
    expect(formatTimeRemaining(const Duration(hours: 48)), '2일');
  });
}
