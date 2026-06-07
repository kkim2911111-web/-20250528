import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notice.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class NoticeService {
  /// 활성 공지 (전체 + 본인 단지). RLS가 필터링합니다.
  Future<List<Notice>> fetchActiveNotices() async {
    if (!isSupabaseInitialized) return [];

    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final rows = await withNetworkRetry(
        () => supabase
            .from('notices')
            .select('id, complex_id, title, content, is_active, created_at')
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(10),
      );

      return (rows as List)
          .map((e) => Notice.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return [];
      rethrow;
    }
  }
}
