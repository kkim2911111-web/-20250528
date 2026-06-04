import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/point_history_entry.dart';
import '../models/point_reservation_summary.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class PointService {
  Future<int> fetchBalance() async {
    return withNetworkRetry(_fetchBalance);
  }

  Future<
      ({
        int balance,
        List<PointHistoryEntry> history,
        Map<String, PointReservationSummary> reservationMeta,
      })> fetchPointSummary() async {
    return withNetworkRetry(_fetchPointSummary);
  }

  Future<int> _fetchBalance() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    try {
      final profile = await supabase
          .from('user_profiles')
          .select('points')
          .eq('user_id', user.id)
          .maybeSingle();
      return (profile?['points'] as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == '42703') return 0;
      rethrow;
    }
  }

  Future<
      ({
        int balance,
        List<PointHistoryEntry> history,
        Map<String, PointReservationSummary> reservationMeta,
      })> _fetchPointSummary() async {
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

    final List<dynamic> rows = await _fetchPointHistoryRows(user.id);

    final history = rows
        .map(
          (e) => PointHistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();

    final reservationMeta = await _loadReservationMeta(user.id, history);

    return (
      balance: balance,
      history: history,
      reservationMeta: reservationMeta,
    );
  }

  /// ```dart
  /// supabase.from('point_history').select().eq('user_id', userId)
  ///     .order('created_at', ascending: false);
  /// ```
  /// type( use / restore / earn / cancel … ) 조건 없이 전체 내역 조회.
  Future<List<dynamic>> _fetchPointHistoryRows(String userId) async {
    try {
      final raw = await supabase
          .from('point_history')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return raw as List<dynamic>? ?? [];
    } on PostgrestException catch (e) {
      if (!_isMissingColumnError(e)) rethrow;
      final raw = await supabase
          .from('point_history')
          .select(
            'id, amount, description, type, balance_after, created_at, reservation_id',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return raw as List<dynamic>? ?? [];
    }
  }

  bool _isMissingColumnError(PostgrestException e) {
    return e.code == '42703' || e.code == 'PGRST204';
  }

  Future<Map<String, PointReservationSummary>> _loadReservationMeta(
    String userId,
    List<PointHistoryEntry> history,
  ) async {
    final ids = <String>{};
    for (final entry in history) {
      final rid = entry.resolvedReservationId;
      if (rid != null && rid.isNotEmpty) ids.add(rid);
    }
    if (ids.isEmpty) return {};

    try {
      final raw = await supabase
          .from('reservations')
          .select(
            'id, start_time, start_at, end_time, end_at, vehicles(model_name)',
          )
          .eq('user_id', userId)
          .inFilter('id', ids.toList());
      final list = raw as List<dynamic>? ?? [];
      return _reservationMetaFromRows(list);
    } catch (_) {
      return {};
    }
  }

  Map<String, PointReservationSummary> _reservationMetaFromRows(
    List<dynamic> list,
  ) {
    final meta = <String, PointReservationSummary>{};
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;

      final vehicleRaw = map['vehicles'];
      var vehicleName = '차량';
      if (vehicleRaw is Map) {
        vehicleName =
            vehicleRaw['model_name']?.toString().trim() ?? vehicleName;
      }
      if (vehicleName.isEmpty) vehicleName = '차량';

      final start = _parseDate(map['start_at'] ?? map['start_time']);
      final end = _parseDate(map['end_at'] ?? map['end_time']);
      var hours = 0;
      if (start != null && end != null && end.isAfter(start)) {
        hours = end.difference(start).inHours;
        if (hours < 1) hours = 1;
      }

      meta[id] = PointReservationSummary(
        vehicleName: vehicleName,
        durationHours: hours,
      );
    }
    return meta;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
