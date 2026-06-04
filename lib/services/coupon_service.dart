import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coupon.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

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
}
