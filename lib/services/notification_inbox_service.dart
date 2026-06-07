import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inbox_notification.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class NotificationInboxService {
  Future<List<InboxNotification>> fetchNotifications({int limit = 50}) async {
    if (!isSupabaseInitialized) return [];

    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final rows = await withNetworkRetry(
        () => supabase
            .from('notifications')
            .select(
              'id, title, body, type, reservation_id, is_read, created_at',
            )
            .order('created_at', ascending: false)
            .limit(limit),
      );

      return (rows as List)
          .map((e) => InboxNotification.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return [];
      rethrow;
    }
  }

  Future<int> fetchUnreadCount() async {
    if (!isSupabaseInitialized) return 0;

    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    try {
      final count = await withNetworkRetry(
        () => supabase
            .from('notifications')
            .count(CountOption.exact)
            .eq('is_read', false),
      );
      return count;
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return 0;
      rethrow;
    }
  }

  Future<void> markRead(String notificationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await withNetworkRetry(
      () => supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId),
    );
  }

  Future<void> markAllRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await withNetworkRetry(
      () => supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('is_read', false),
    );
  }
}
