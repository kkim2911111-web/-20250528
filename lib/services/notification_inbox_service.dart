import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inbox_notification.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class NotificationInboxService {
  Future<List<InboxNotification>> fetchNotifications({
    int limit = 50,
    bool onlyOwnRows = false,
  }) async {
    if (!isSupabaseInitialized) return [];

    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final rows = await withNetworkRetry(
        () {
          var query = supabase
              .from('notifications')
              .select(
                'id, title, body, type, reservation_id, is_read, created_at',
              );
          if (onlyOwnRows) {
            query = query.eq('user_id', user.id);
          }
          return query
              .order('created_at', ascending: false)
              .limit(limit);
        },
      );

      return (rows as List)
          .map((e) => InboxNotification.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return [];
      rethrow;
    }
  }

  Future<int> fetchUnreadCount({bool onlyOwnRows = false}) async {
    if (!isSupabaseInitialized) return 0;

    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    try {
      final count = await withNetworkRetry(
        () {
          var query = supabase
              .from('notifications')
              .count(CountOption.exact)
              .eq('is_read', false);
          if (onlyOwnRows) {
            query = query.eq('user_id', user.id);
          }
          return query;
        },
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

  Future<void> markAllRead({bool onlyOwnRows = false}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await withNetworkRetry(
      () {
        var query = supabase
            .from('notifications')
            .update({'is_read': true})
            .eq('is_read', false);
        if (onlyOwnRows) {
          query = query.eq('user_id', user.id);
        }
        return query;
      },
    );
  }
}
