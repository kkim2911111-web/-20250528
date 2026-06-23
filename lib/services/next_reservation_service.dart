import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reservation.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';
import '../utils/reservation_overlap.dart';

/// 다음 예약 조회·연장 충돌 판별
class NextReservationService {
  static const blockingStatuses = ['confirmed', 'pending', 'in_use'];

  /// 종료 직후 버퍼 안 다음 예약 (레거시)
  Future<bool> hasNextReservationInBuffer({
    required String vehicleId,
    required DateTime currentEndAt,
    String? excludeReservationId,
  }) async {
    if (!isSupabaseInitialized) return false;
    if (supabase.auth.currentUser == null) return false;
    if (vehicleId.trim().isEmpty) return false;

    final endUtc = currentEndAt.toUtc();
    final bufferEndUtc =
        endUtc.add(ReservationOverlapLogic.postReturnBookingBuffer);

    try {
      var query = supabase
          .from('reservations')
          .select('id')
          .eq('vehicle_id', vehicleId)
          .inFilter('status', blockingStatuses)
          .gt('start_at', endUtc.toIso8601String())
          .lt('start_at', bufferEndUtc.toIso8601String());

      final exclude = excludeReservationId?.trim();
      if (exclude != null && exclude.isNotEmpty) {
        query = query.neq('id', exclude);
      }

      final rows = await withNetworkRetry(() => query.limit(1));
      return (rows as List).isNotEmpty;
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return false;
      rethrow;
    }
  }

  /// 현재 종료 이후 가장 빠른 차단 예약
  Future<NextBlockingReservation?> fetchNextBlockingReservation({
    required String vehicleId,
    required DateTime afterEndAt,
    String? excludeReservationId,
  }) async {
    if (!isSupabaseInitialized) return null;
    if (supabase.auth.currentUser == null) return null;
    if (vehicleId.trim().isEmpty) return null;

    try {
      var query = supabase
          .from('reservations')
          .select('id, start_at, end_at, status')
          .eq('vehicle_id', vehicleId)
          .inFilter('status', ['confirmed', 'in_use'])
          .gt('start_at', afterEndAt.toUtc().toIso8601String());

      final exclude = excludeReservationId?.trim();
      if (exclude != null && exclude.isNotEmpty) {
        query = query.neq('id', exclude);
      }

      final rows = await withNetworkRetry(
        () => query.order('start_at', ascending: true).limit(1),
      );
      final list = rows as List;
      if (list.isEmpty) return null;

      final row = Map<String, dynamic>.from(list.first as Map);
      final startRaw = row['start_at'];
      if (startRaw == null) return null;

      return NextBlockingReservation(
        id: row['id']?.toString() ?? '',
        startAt: DateTime.parse(startRaw.toString()).toLocal(),
        endAt: row['end_at'] != null
            ? DateTime.parse(row['end_at'].toString()).toLocal()
            : null,
        status: row['status']?.toString() ?? 'confirmed',
      );
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return null;
      rethrow;
    }
  }

  /// 연장 구간 [currentEnd, newEnd]가 다른 예약과 겹치는지
  Future<bool> extensionConflictsWithOthers({
    required String vehicleId,
    required DateTime currentEnd,
    required DateTime newEnd,
    String? excludeReservationId,
  }) async {
    if (!newEnd.isAfter(currentEnd)) return true;
    if (!isSupabaseInitialized) return false;
    if (supabase.auth.currentUser == null) return false;

    try {
      var query = supabase
          .from('reservations')
          .select('id, start_at, end_at, status, actual_end_at, returned_at')
          .eq('vehicle_id', vehicleId)
          .inFilter('status', ['confirmed', 'in_use']);

      final exclude = excludeReservationId?.trim();
      if (exclude != null && exclude.isNotEmpty) {
        query = query.neq('id', exclude);
      }

      final rows = await withNetworkRetry(() => query);
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final startRaw = row['start_at'];
        if (startRaw == null) continue;
        final otherStart = DateTime.parse(startRaw.toString()).toLocal();
        final otherEnd = row['end_at'] != null
            ? DateTime.parse(row['end_at'].toString()).toLocal()
            : null;
        final otherActual = row['actual_end_at'] != null
            ? DateTime.parse(row['actual_end_at'].toString()).toLocal()
            : null;
        final otherReturned = row['returned_at'] != null
            ? DateTime.parse(row['returned_at'].toString()).toLocal()
            : null;

        if (ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: row['status']?.toString() ?? 'confirmed',
          otherScheduledEnd: otherEnd,
          otherActualEndAt: otherActual,
          otherReturnedAt: otherReturned,
          requestStart: currentEnd,
          requestEnd: newEnd,
        )) {
          return true;
        }
      }
      return false;
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return false;
      rethrow;
    }
  }

  Future<Map<String, bool>> checkForReservations(
    Iterable<Reservation> reservations,
  ) async {
    final result = <String, bool>{};
    for (final reservation in reservations) {
      if (!reservation.isInUse) continue;
      final endAt = reservation.endAt;
      if (endAt == null) continue;
      result[reservation.id] = await hasNextReservationInBuffer(
        vehicleId: reservation.vehicleId,
        currentEndAt: endAt,
        excludeReservationId: reservation.id,
      );
    }
    return result;
  }
}

class NextBlockingReservation {
  final String id;
  final DateTime startAt;
  final DateTime? endAt;
  final String status;

  const NextBlockingReservation({
    required this.id,
    required this.startAt,
    this.endAt,
    required this.status,
  });
}
