import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/point_history_entry.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class PointService {
  Future<({int balance, List<PointHistoryEntry> history})> fetchPointSummary() async {
    return withNetworkRetry(_fetchPointSummary);
  }

  Future<({int balance, List<PointHistoryEntry> history})> _fetchPointSummary() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    var balance = 0;
    try {
      final profile = await supabase
          .from('user_profiles')
          .select('points')
          .eq('user_id', user.id)
          .maybeSingle();
      balance = (profile?['points'] as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      if (e.code != '42P01' && e.code != '42703') rethrow;
    }

    final rows = await supabase
        .from('point_history')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final list = rows as List<dynamic>? ?? [];
    final history = list
        .map(
          (e) => PointHistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();

    return (balance: balance, history: history);
  }
}
