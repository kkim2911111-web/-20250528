import 'package:flutter/foundation.dart';

/// 예약 생성·취소 후 홈·내 예약 등 목록 새로고침용
class ReservationRefreshBus {
  ReservationRefreshBus._();

  static final ReservationRefreshBus instance = ReservationRefreshBus._();

  final version = ValueNotifier<int>(0);

  void notifyChanged() {
    version.value++;
  }
}
