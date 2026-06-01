import '../supabase_client.dart';
import 'supabase_bootstrap.dart';

/// reservations 테이블 스키마 사전 점검 (door_unlocked 등)
abstract final class ReservationSchemaService {
  static bool? _doorColumnOk;

  static bool get isDoorColumnAvailable => _doorColumnOk ?? true;

  /// 앱 시작 시 1회 — door_unlocked 컬럼 존재 여부 확인
  static Future<bool> probeDoorUnlockedColumn() async {
    if (_doorColumnOk != null) return _doorColumnOk!;
    if (!isSupabaseBootstrapReady) {
      _doorColumnOk = true;
      return true;
    }

    try {
      await supabase.from('reservations').select('door_unlocked').limit(1);
      _doorColumnOk = true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('door_unlocked') ||
          msg.contains('42703') ||
          msg.contains('does not exist')) {
        _doorColumnOk = false;
      } else {
        _doorColumnOk = true;
      }
    }
    return _doorColumnOk!;
  }

  static const doorColumnMissingMessage =
      '차량 문 제어를 위한 door_unlocked 컬럼이 없습니다.\n'
      'Supabase SQL Editor에서 fix_reservations_schema.sql 을 실행해주세요.';
}
