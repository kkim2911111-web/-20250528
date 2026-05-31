import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_banner.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class BannerService {
  /// is_active = true 인 첫 번째 배너 (id 오름차순)
  Future<HomeBanner?> fetchActiveBanner() async {
    if (!isSupabaseInitialized) return null;

    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final row = await withNetworkRetry(
        () => supabase
            .from('banners')
            .select('id, sub_title, main_title, description, is_active, created_at')
            .eq('is_active', true)
            .order('id', ascending: true)
            .limit(1)
            .maybeSingle(),
      );

      if (row == null) return null;
      return HomeBanner.fromMap(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return null;
      rethrow;
    }
  }
}
