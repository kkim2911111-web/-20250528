import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/local_spot.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class LocalSpotService {
  Future<List<LocalSpot>> fetchLocalSpots() async {
    if (!isSupabaseInitialized) return [];

    try {
      final rows = await withNetworkRetry(
        () => supabase
            .from('local_spots')
            .select(
              'id, name, short_name, description, image_url, rating, tags, '
              'distance_text, is_featured, phone_number, sort_order',
            )
            .order('sort_order', ascending: true)
            .order('created_at', ascending: true),
      );

      return (rows as List)
          .map((e) => LocalSpot.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return [];
      rethrow;
    }
  }
}
