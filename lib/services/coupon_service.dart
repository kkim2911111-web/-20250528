import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coupon.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

/// `grant_welcome_coupon` RPC 결과
class WelcomeCouponGrantResult {
  final bool granted;
  final bool skipped;

  const WelcomeCouponGrantResult({
    required this.granted,
    this.skipped = false,
  });

  factory WelcomeCouponGrantResult.fromRpc(Object? data) {
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final skipped = map['skipped'] == true;
    final granted = map['granted'] == true;
    return WelcomeCouponGrantResult(granted: granted, skipped: skipped);
  }
}

class CouponService {
  Future<List<UserCoupon>> fetchMyCoupons() async {
    return withNetworkRetry(_fetchMyCoupons);
  }

  Future<List<UserCoupon>> _fetchMyCoupons() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    dynamic rows;
    try {
      rows = await supabase
          .from('user_coupons')
          .select('*, coupons(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        rows = await supabase
            .from('user_coupons')
            .select('*, coupons(*)')
            .eq('user_id', user.id)
            .order('issued_at', ascending: false);
      } else {
        rethrow;
      }
    }

    final list = rows as List<dynamic>? ?? [];
    return list
        .map((e) => UserCoupon.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 예약 결제 — 미사용·미만료 쿠폰만
  Future<List<UserCoupon>> fetchAvailableCoupons() async {
    final all = await fetchMyCoupons();
    return all.where((c) => c.isCouponAvailableTab).toList();
  }

  /// 온보딩 5단계 완료 — 가입 축하 쿠폰 발급 (중복 시 skipped)
  Future<WelcomeCouponGrantResult> grantWelcomeCoupon() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final data = await supabase.rpc(
      'grant_welcome_coupon',
      params: {'p_user_id': user.id},
    );
    return WelcomeCouponGrantResult.fromRpc(data);
  }
}
