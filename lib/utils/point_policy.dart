/// 확정된 포인트 사용·표시 정책
abstract final class PointPolicy {
  static const minUseAmount = 5000;

  static bool canUsePoints(int balance) => balance >= minUseAmount;

  static bool isValidUseAmount(int amount) =>
      amount == 0 || amount >= minUseAmount;
}
