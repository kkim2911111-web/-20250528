import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inspection_photo.dart';
import '../models/super_admin_models.dart';
import '../supabase_client.dart';
import '../utils/inspection_photo_resolver.dart';

class SuperAdminException implements Exception {
  final String message;
  const SuperAdminException(this.message);
  @override
  String toString() => message;
}

class BlacklistEnforceResult {
  final int cancelledCount;

  const BlacklistEnforceResult({this.cancelledCount = 0});
}

class SuperAdminService {
  Future<bool> isSuperAdmin() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    try {
      final row = await supabase
          .from('user_profiles')
          .select('is_super_admin')
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['is_super_admin'] == true;
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == '42P01') return false;
      rethrow;
    }
  }

  Future<T> _rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    required T Function(dynamic data) parse,
  }) async {
    try {
      final data = await supabase.rpc(fn, params: params ?? {});
      return parse(data);
    } on PostgrestException catch (e) {
      throw SuperAdminException(_mapError(e));
    }
  }

  Future<SuperAdminDashboard> fetchDashboard() => _rpc(
        'get_super_admin_dashboard',
        parse: (d) {
          final row = d is List && d.isNotEmpty
              ? Map<String, dynamic>.from(d.first as Map)
              : <String, dynamic>{};
          return SuperAdminDashboard.fromMap(row);
        },
      );

  Future<List<SuperAdminComplex>> fetchComplexes() => _rpc(
        'get_super_admin_complexes',
        parse: (d) => _list(d, SuperAdminComplex.fromMap),
      );

  Future<List<SuperAdminVehicle>> fetchVehicles() => _rpc(
        'get_super_admin_vehicles',
        parse: (d) => _list(d, SuperAdminVehicle.fromMap),
      );

  Future<List<SuperAdminStaff>> fetchStaff() => _rpc(
        'get_super_admin_staff',
        parse: (d) => _list(d, SuperAdminStaff.fromMap),
      );

  Future<List<SuperAdminResident>> fetchResidents() => _rpc(
        'get_super_admin_residents',
        parse: (d) => _list(d, SuperAdminResident.fromMap),
      );

  Future<SuperAdminResidentDetail> fetchResidentDetail(String userId) => _rpc(
        'get_super_admin_resident_detail',
        params: {'p_user_id': userId},
        parse: (d) => SuperAdminResidentDetail.fromMap(
          Map<String, dynamic>.from(d as Map),
        ),
      );

  Future<Map<String, Set<String>>> fetchReservationUserIndex() => _rpc(
        'get_super_admin_reservation_user_ids',
        parse: (d) {
          final index = <String, Set<String>>{};
          if (d is! List) return index;
          for (final row in d) {
            final m = Map<String, dynamic>.from(row as Map);
            final userId = m['user_id']?.toString();
            final reservationId = m['reservation_id']?.toString();
            if (userId == null ||
                userId.isEmpty ||
                reservationId == null ||
                reservationId.isEmpty) {
              continue;
            }
            index.putIfAbsent(userId, () => <String>{}).add(reservationId);
          }
          return index;
        },
      );

  Future<String?> fetchReservationContract(String reservationId) async {
    final id = reservationId.trim();
    if (id.isEmpty) return null;
    try {
      final data = await supabase.rpc(
        'get_super_admin_reservation_contract',
        params: {'p_reservation_id': id},
      );
      final text = data?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } on PostgrestException catch (e) {
      throw SuperAdminException(_mapError(e));
    }
  }

  Future<String?> ensureReservationContract(String reservationId) async {
    final id = reservationId.trim();
    if (id.isEmpty) {
      throw const SuperAdminException('예약번호가 없습니다.');
    }

    final cached = await fetchReservationContract(id);
    if (cached != null && cached.isNotEmpty) return cached;

    await _rpc(
      'generate_rental_contract_for_super_admin',
      params: {'p_reservation_id': id},
      parse: (_) {},
    );

    return fetchReservationContract(id);
  }

  Future<List<SuperAdminReservation>> fetchReservations() => _rpc(
        'get_super_admin_reservations',
        parse: (d) => _list(d, SuperAdminReservation.fromMap),
      );

  /// 임차인 이용·노쇼 건수 — 전 기간 count RPC (바텀시트 열 때 1회)
  Future<SuperAdminRenterUsageStats> fetchRenterUsageStats({
    required String reservationId,
  }) async {
    final id = reservationId.trim();
    if (id.isEmpty) return SuperAdminRenterUsageStats.empty;

    return _rpc(
      'get_super_admin_renter_usage_stats',
      params: {'p_reservation_id': id},
      parse: (d) {
        if (d is List && d.isNotEmpty) {
          final row = Map<String, dynamic>.from(d.first as Map);
          return SuperAdminRenterUsageStats(
            usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
            noShowCount: (row['no_show_count'] as num?)?.toInt() ?? 0,
          );
        }
        if (d is Map) {
          final row = Map<String, dynamic>.from(d);
          return SuperAdminRenterUsageStats(
            usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
            noShowCount: (row['no_show_count'] as num?)?.toInt() ?? 0,
          );
        }
        return SuperAdminRenterUsageStats.empty;
      },
    );
  }

  bool canDeleteStaff(
    SuperAdminStaff staff, {
    required List<SuperAdminStaff> allStaff,
  }) {
    final peers = allStaff.where((s) => s.complexId == staff.complexId).length;
    return peers > 1;
  }

  /// 검수 사진 — get_super_admin_reservations RPC 결과 최우선
  Future<InspectionPhotoSet> fetchInspectionPhotoSet(
    SuperAdminReservation reservation,
  ) async {
    var before = normalizeInspectionPhotoUrls(reservation.pickupPhotos);
    var after = normalizeInspectionPhotoUrls(reservation.returnPhotos);

    var rentalStartedAt = reservation.rentalStartedAt;
    var returnedAt = reservation.returnedAt;
    var actualEndAt = reservation.actualEndAt;
    var status = reservation.status;
    DateTime? updatedAt;

    if (before.isEmpty || after.isEmpty) {
      try {
        final row = await supabase
            .from('reservations')
            .select(
              'pickup_photos, return_photos, rental_started_at, returned_at, '
              'actual_end_at, status, updated_at',
            )
            .eq('id', reservation.id)
            .maybeSingle();

        if (row != null) {
          if (before.isEmpty) {
            before = normalizeInspectionPhotoUrls(
              _photoUrlsFromValue(row['pickup_photos']),
            );
          }
          if (after.isEmpty) {
            after = normalizeInspectionPhotoUrls(
              _photoUrlsFromValue(row['return_photos']),
            );
          }
          rentalStartedAt =
              _parseDate(row['rental_started_at']) ?? rentalStartedAt;
          returnedAt = _parseDate(row['returned_at']) ?? returnedAt;
          actualEndAt = _parseDate(row['actual_end_at']) ?? actualEndAt;
          status = row['status']?.toString() ?? status;
          updatedAt = _parseDate(row['updated_at']);
        }
      } catch (_) {
        // RLS 미허용 시 ride_photos 폴백으로 진행
      }
    }

    final beforeRecords = await _fetchRidePhotoRecordsForSuperAdmin(
      reservationId: reservation.id,
      photoType: 'before',
    );
    final afterRecords = await _fetchRidePhotoRecordsForSuperAdmin(
      reservationId: reservation.id,
      photoType: 'after',
    );

    if (before.isEmpty) {
      before = normalizeInspectionPhotoUrls(
        beforeRecords.map((record) => record.url),
      );
    }
    if (after.isEmpty) {
      after = normalizeInspectionPhotoUrls(
        afterRecords.map((record) => record.url),
      );
    }

    return buildInspectionPhotoSet(
      beforeUrls: before,
      afterUrls: after,
      rentalStartedAt: rentalStartedAt,
      returnedAt: returnedAt,
      actualEndAt: actualEndAt,
      status: status,
      updatedAt: updatedAt,
      beforeTimestampsByUrl: ridePhotoTimestampsByUrl(beforeRecords),
      afterTimestampsByUrl: ridePhotoTimestampsByUrl(afterRecords),
    );
  }

  static ({String url, DateTime? createdAt}) _parseRidePhotoRow(dynamic row) {
    if (row is Map) {
      return (
        url: row['photo_url']?.toString().trim() ?? '',
        createdAt: _parseDate(row['created_at']),
      );
    }
    return (url: row?.toString().trim() ?? '', createdAt: null);
  }

  Future<List<({String url, DateTime? createdAt})>>
      _fetchRidePhotoRecordsForSuperAdmin({
    required String reservationId,
    required String photoType,
  }) async {
    try {
      final data = await supabase.rpc('get_ride_photos_for_staff', params: {
        'p_reservation_id': reservationId,
        'p_photo_type': photoType,
      });
      if (data is! List) return const [];
      return data
          .map(_parseRidePhotoRow)
          .where((record) => record.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _photoUrlsFromValue(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<List<SuperAdminRevenueRow>> fetchRevenue({
    int? year,
    int? month,
  }) =>
      _rpc(
        'get_super_admin_revenue',
        params: {
          if (year != null) 'p_year': year,
          if (month != null) 'p_month': month,
        },
        parse: (d) => _list(d, SuperAdminRevenueRow.fromMap),
      );

  Future<SuperAdminSettlementSheet> fetchSettlementSheet({
    required String complexId,
    required int year,
    required int month,
  }) =>
      _rpc(
        'get_super_admin_settlement_reservations',
        params: {
          'p_complex_id': complexId,
          'p_year': year,
          'p_month': month,
        },
        parse: (d) => SuperAdminSettlementSheet.fromRpc(d),
      );

  Future<List<SuperAdminCoupon>> fetchCoupons() => _rpc(
        'get_super_admin_coupons',
        parse: (d) => _list(d, SuperAdminCoupon.fromMap),
      );

  Future<List<SuperAdminBanner>> fetchBanners() => _rpc(
        'get_super_admin_banners',
        parse: (d) => _list(d, SuperAdminBanner.fromMap),
      );

  Future<List<SuperAdminNotice>> fetchNotices() => _rpc(
        'get_super_admin_notices',
        parse: (d) => _list(d, SuperAdminNotice.fromMap),
      );

  Future<Map<String, dynamic>> fetchSettings() => _rpc(
        'get_super_admin_settings',
        parse: (d) => d is Map ? Map<String, dynamic>.from(d) : {},
      );

  Future<String> upsertComplex({
    String? id,
    required String name,
    String? inviteCode,
    String? adminInviteCode,
    String? businessName,
    String? businessPhone,
  }) =>
      _rpc(
        'upsert_super_admin_complex',
        params: {
          if (id != null) 'p_complex_id': id,
          'p_name': name,
          if (inviteCode != null) 'p_invite_code': inviteCode,
          if (adminInviteCode != null) 'p_admin_invite_code': adminInviteCode,
          if (businessName != null) 'p_business_name': businessName,
          if (businessPhone != null) 'p_business_phone': businessPhone,
        },
        parse: (d) => d?.toString() ?? '',
      );

  Future<void> deleteComplex(String id) => _rpc(
        'delete_super_admin_complex',
        params: {'p_complex_id': id},
        parse: (_) {},
      );

  Future<String> upsertVehicle({
    String? id,
    required String complexId,
    required String modelName,
    String vehicleType = 'SUV',
    String? fuelType,
    int pricePerHour = 0,
    String? carNumber,
    bool isAvailable = true,
    int? dailyPrice,
    int? monthlyPrice,
    int? monthlyExcessDailyPrice,
    List<String>? rentalTypes,
  }) =>
      _rpc(
        'upsert_super_admin_vehicle',
        params: {
          if (id != null) 'p_vehicle_id': id,
          'p_complex_id': complexId,
          'p_model_name': modelName,
          'p_vehicle_type': vehicleType,
          if (fuelType != null) 'p_fuel_type': fuelType,
          'p_price_per_hour': pricePerHour,
          if (carNumber != null) 'p_car_number': carNumber,
          'p_is_available': isAvailable,
          'p_daily_price': dailyPrice,
          'p_monthly_price': monthlyPrice,
          'p_monthly_excess_daily_price': monthlyExcessDailyPrice,
          if (rentalTypes != null) 'p_rental_types': rentalTypes,
        },
        parse: (d) => d?.toString() ?? '',
      );

  Future<void> deleteVehicle(String id) => _rpc(
        'delete_super_admin_vehicle',
        params: {'p_vehicle_id': id},
        parse: (_) {},
      );

  Future<void> setStaffApproved(String userId, bool approved) => _rpc(
        'set_super_admin_staff_approved',
        params: {'p_user_id': userId, 'p_approved': approved},
        parse: (_) {},
      );

  Future<void> setStaffComplex(String userId, String complexId) => _rpc(
        'set_super_admin_staff_complex',
        params: {'p_user_id': userId, 'p_complex_id': complexId},
        parse: (_) {},
      );

  Future<void> deleteStaff(String userId) => _rpc(
        'delete_super_admin_staff',
        params: {'p_user_id': userId},
        parse: (_) {},
      );

  Future<void> setResidentApproved(String userId, bool approved) => _rpc(
        'set_super_admin_resident_approved',
        params: {'p_user_id': userId, 'p_approved': approved},
        parse: (_) {},
      );

  Future<void> deleteResident(String userId) => _rpc(
        'delete_super_admin_resident',
        params: {'p_user_id': userId},
        parse: (_) {},
      );

  Future<BlacklistEnforceResult> setBlacklist(
    String userId,
    bool blacklisted,
  ) async {
    if (blacklisted) {
      try {
        final res = await supabase.functions.invoke(
          'enforce-user-blacklist',
          body: {'userId': userId, 'blacklisted': true},
        );
        if (res.status != 200) {
          final data = res.data;
          final msg = data is Map
              ? data['error']?.toString()
              : res.status.toString();
          throw SuperAdminException(
            msg?.isNotEmpty == true ? msg! : '블랙리스트 등록에 실패했습니다.',
          );
        }
        final data = res.data;
        if (data is Map) {
          return BlacklistEnforceResult(
            cancelledCount: (data['cancelledCount'] as num?)?.toInt() ?? 0,
          );
        }
        return const BlacklistEnforceResult();
      } on FunctionException catch (e) {
        final details = e.details;
        if (details is Map && details['error'] != null) {
          throw SuperAdminException(details['error'].toString());
        }
        throw SuperAdminException(
          e.reasonPhrase ?? '블랙리스트 등록에 실패했습니다.',
        );
      }
    }

    await _rpc(
      'set_super_admin_user_blacklist',
      params: {'p_user_id': userId, 'p_blacklisted': false},
      parse: (_) {},
    );
    return const BlacklistEnforceResult();
  }

  Future<void> forceLicenseApproved(String userId) => _rpc(
        'force_super_admin_license_approved',
        params: {'p_user_id': userId},
        parse: (_) {},
      );

  Future<void> forceLicenseRejected(String userId, {String? reason}) => _rpc(
        'force_super_admin_license_rejected',
        params: {
          'p_user_id': userId,
          if (reason != null) 'p_reason': reason,
        },
        parse: (_) {},
      );

  Future<String> upsertCoupon({
    String? id,
    required String title,
    int discountAmount = 0,
    int minAmount = 0,
    String? code,
  }) =>
      _rpc(
        'upsert_super_admin_coupon',
        params: {
          if (id != null) 'p_coupon_id': id,
          'p_title': title,
          'p_discount_amount': discountAmount,
          'p_min_amount': minAmount,
          if (code != null) 'p_code': code,
        },
        parse: (d) => d?.toString() ?? '',
      );

  Future<void> deleteCoupon(String id) => _rpc(
        'delete_super_admin_coupon',
        params: {'p_coupon_id': id},
        parse: (_) {},
      );

  Future<void> issueCoupon({
    required String userId,
    required String couponId,
    required String couponTitle,
    DateTime? expiresAt,
  }) async {
    await _rpc(
      'issue_super_admin_coupon',
      params: {
        'p_user_id': userId,
        'p_coupon_id': couponId,
        if (expiresAt != null) 'p_expires_at': expiresAt.toUtc().toIso8601String(),
      },
      parse: (_) {},
    );
    await _sendCouponIssuedPushes(
      userIds: [userId],
      couponTitle: couponTitle,
    );
  }

  /// 일괄 발급 — p_complexId null·userIds null이면 전체 입주민
  /// 개별 / 단지별 / 전체 발급 후 발급 대상에게 푸시 발송
  Future<BulkIssueCouponResult> bulkIssueCoupon({
    required String couponId,
    required String couponTitle,
    String? complexId,
    List<String>? userIds,
  }) async {
    final result = await _rpc(
      'bulk_issue_coupon',
      params: {
        'p_coupon_id': couponId,
        if (complexId != null) 'p_complex_id': complexId,
        if (userIds != null && userIds.isNotEmpty) 'p_user_ids': userIds,
      },
      parse: (d) {
        if (d is Map) {
          return BulkIssueCouponResult.fromMap(Map<String, dynamic>.from(d));
        }
        return const BulkIssueCouponResult();
      },
    );

    final pushTargets = result.issuedUserIds.isNotEmpty
        ? result.issuedUserIds
        : (userIds ?? const <String>[]);

    if (result.issuedCount > 0 && pushTargets.isEmpty) {
      debugPrint(
        '[coupon-push] issued_count=${result.issuedCount} but issued_user_ids '
        'empty — apply migration 20260528120000_bulk_issue_coupon_issued_user_ids',
      );
    }

    if (pushTargets.isNotEmpty) {
      await _sendCouponIssuedPushes(
        userIds: pushTargets,
        couponTitle: couponTitle,
      );
    } else {
      debugPrint('[coupon-push] skip — no push targets after bulk issue');
    }

    return result;
  }

  /// send-push-notification Edge Function — 유저별 FCM 토큰 조회·발송
  Future<void> _sendCouponIssuedPushes({
    required List<String> userIds,
    required String couponTitle,
  }) async {
    const title = '쿠폰이 도착했어요 🎫';
    final name = couponTitle.trim().isEmpty ? '쿠폰' : couponTitle.trim();
    final body = '[$name] 쿠폰이 발급되었습니다. 지금 확인해보세요.';

    debugPrint(
      '[coupon-push] start count=${userIds.length} title=$title type=coupon',
    );

    for (final userId in userIds) {
      final uid = userId.trim();
      if (uid.isEmpty) continue;

      final payload = {
        'userId': uid,
        'title': title,
        'body': body,
        'type': 'coupon',
      };

      try {
        final response = await supabase.functions.invoke(
          'send-push-notification',
          body: payload,
        );

        if (response.status != 200) {
          final err = response.data is Map
              ? response.data['error']?.toString()
              : response.data?.toString();
          debugPrint(
            '[coupon-push] failed userId=$uid status=${response.status} '
            'error=${err ?? 'unknown'} payload=$payload',
          );
          continue;
        }

        final data = response.data;
        final sent = data is Map ? data['sent'] : null;
        final tokens = data is Map ? data['tokens'] : null;
        debugPrint(
          '[coupon-push] ok userId=$uid sent=$sent tokens=$tokens',
        );
      } catch (e, st) {
        debugPrint(
          '[coupon-push] exception userId=$uid error=$e payload=$payload',
        );
        debugPrint('[coupon-push] stack: $st');
      }
    }
  }

  /// in_use 예약 → returned (반납 검수 화면)
  Future<void> forceReturnReservation(String id) => _rpc(
        'force_return_reservation_for_super_admin',
        params: {'p_reservation_id': id},
        parse: (_) {},
      );

  /// 결제취소 — Toss 환불 + 예약/결제 취소
  Future<void> forcePaymentCancelReservation(String id) async {
    final response = await supabase.functions.invoke(
      'admin-force-payment-cancel',
      body: {'reservationId': id},
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map
          ? data['error']?.toString() ?? '결제취소에 실패했습니다.'
          : '결제취소에 실패했습니다.';
      throw SuperAdminException(message);
    }
  }

  Future<void> markSettlement({
    required String complexId,
    required int year,
    required int month,
    String? note,
  }) =>
      _rpc(
        'mark_super_admin_settlement',
        params: {
          'p_complex_id': complexId,
          'p_year': year,
          'p_month': month,
          if (note != null) 'p_note': note,
        },
        parse: (_) {},
      );

  Future<int> upsertBanner({
    int? id,
    required String subTitle,
    required String mainTitle,
    required String description,
    bool isActive = true,
  }) =>
      _rpc(
        'upsert_super_admin_banner',
        params: {
          if (id != null) 'p_banner_id': id,
          'p_sub_title': subTitle,
          'p_main_title': mainTitle,
          'p_description': description,
          'p_is_active': isActive,
        },
        parse: (d) => (d as num?)?.toInt() ?? 0,
      );

  Future<void> deleteBanner(int id) => _rpc(
        'delete_super_admin_banner',
        params: {'p_banner_id': id},
        parse: (_) {},
      );

  Future<String> upsertNotice({
    String? id,
    String? complexId,
    required String title,
    required String content,
    bool isActive = true,
  }) =>
      _rpc(
        'upsert_super_admin_notice',
        params: {
          if (id != null) 'p_notice_id': id,
          'p_complex_id': complexId,
          'p_title': title,
          'p_content': content,
          'p_is_active': isActive,
        },
        parse: (d) => d?.toString() ?? '',
      );

  Future<void> deleteNotice(String id) => _rpc(
        'delete_super_admin_notice',
        params: {'p_notice_id': id},
        parse: (_) {},
      );

  Future<void> setMaintenance({required bool enabled, String? message}) =>
      _rpc(
        'set_super_admin_maintenance',
        params: {
          'p_enabled': enabled,
          if (message != null) 'p_message': message,
        },
        parse: (_) {},
      );

  /// 전체 푸시 — user_profiles 기준 (최대 limit명)
  Future<int> broadcastPush({
    required String title,
    required String body,
    int limit = 200,
  }) async {
    final rows = await supabase
        .from('user_profiles')
        .select('user_id')
        .limit(limit);
    var sent = 0;
    for (final row in rows as List) {
      final userId = row['user_id']?.toString();
      if (userId == null || userId.isEmpty) continue;
      try {
        final res = await supabase.functions.invoke(
          'send-push-notification',
          body: {
            'userId': userId,
            'title': title,
            'body': body,
            'type': 'admin_broadcast',
          },
        );
        if (res.status == 200) sent++;
      } catch (_) {}
    }
    return sent;
  }

  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) fromMap) {
    if (data == null) return [];
    return (data as List)
        .map((e) => fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  String _mapError(PostgrestException e) {
    final m = e.message.toLowerCase();
    if (m.contains('super_admin_required')) {
      return '최고관리자 권한이 필요합니다.';
    }
    if (m.contains('not_authenticated')) return '로그인이 필요합니다.';
    if (m.contains('reservation_not_found')) return '예약을 찾을 수 없습니다.';
    if (m.contains('invalid_status')) return '처리할 수 없는 예약 상태입니다.';
    if (m.contains('staff_has_assigned_complex')) {
      return '담당 단지가 있어 삭제할 수 없습니다. 단지 변경으로 인계 후 삭제하세요.';
    }
    if (m.contains('staff_not_found')) return '스태프를 찾을 수 없습니다.';
    return e.message;
  }
}

String friendlySuperAdminError(Object e) {
  if (e is SuperAdminException) return e.message;
  if (e is PostgrestException) return e.message;
  return e.toString();
}
