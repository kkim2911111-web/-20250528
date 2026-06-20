import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_customer.dart';
import '../models/admin_timeline.dart';
import '../models/inspection_photo.dart';
import '../models/license_review_item.dart';
import '../models/resident_review_item.dart';
import '../models/vehicle_maintenance.dart';
import '../models/notice.dart';
import '../models/staff_profile.dart';
import '../models/super_admin_models.dart';
import '../utils/admin_conflict.dart';
import '../utils/inspection_photo_resolver.dart';
import '../utils/vehicle_insurance_status.dart';
import '../repositories/staff_repository.dart';
import '../supabase_client.dart';
import 'push_notification_service.dart';

class AdminException implements Exception {
  final String message;
  const AdminException(this.message);
  @override
  String toString() => message;
}

class SendPushResult {
  final int sent;
  final int tokens;
  final bool skipped;

  const SendPushResult({
    required this.sent,
    required this.tokens,
    required this.skipped,
  });
}

class AdminService {
  final _staffRepo = StaffRepository();

  static const invalidInviteCodeMessage = '초대코드가 올바르지 않습니다.';

  static const vehicleTypes = [
    '경차',
    '세단',
    'SUV',
    'MPV',
    '전기 SUV',
    '전기 세단',
    '트럭',
    '기타',
  ];

  static const fuelTypes = [
    '휘발유',
    '경유',
    'LPG',
    '전기',
    '하이브리드',
    '수소',
  ];

  Future<StaffProfile?> fetchMyProfile() => _staffRepo.fetchMyProfile();

  /// 관리자 → 특정 유저 FCM 푸시 (Edge Function send-push-notification)
  Future<SendPushResult> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    String? type,
    String? reservationId,
  }) async {
    final response = await supabase.functions.invoke(
      'send-push-notification',
      body: {
        'userId': userId,
        'title': title,
        'body': body,
        if (type != null && type.isNotEmpty) 'type': type,
        if (reservationId != null && reservationId.isNotEmpty)
          'reservationId': reservationId,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map
          ? data['error']?.toString() ?? '푸시 발송에 실패했습니다.'
          : '푸시 발송에 실패했습니다.';
      throw AdminException(message);
    }

    final data = response.data;
    if (data is! Map) {
      throw const AdminException('푸시 발송 응답이 올바르지 않습니다.');
    }

    return SendPushResult(
      sent: (data['sent'] as num?)?.toInt() ?? 0,
      tokens: (data['tokens'] as num?)?.toInt() ?? 0,
      skipped: data['skipped'] == true,
    );
  }

  /// 관리자 가입 — RPC 후 staff_users 레코드 확인까지
  Future<StaffProfile> registerStaff({
    required String displayName,
    required String adminInviteCode,
    required String phone,
    required String companyName,
  }) async {
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;
    if (session == null || user == null) {
      throw const AdminException(
        '로그인 세션이 없습니다. 이메일 인증을 완료한 뒤 다시 시도해주세요.',
      );
    }

    final normalizedCode = adminInviteCode
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();

    debugPrint(
      '[register_staff_for_me] call uid=${user.id} '
      'invite=$normalizedCode name=${displayName.trim()}',
    );

    try {
      final rpcRaw = await supabase.rpc('register_staff_for_me', params: {
        'p_display_name': displayName.trim(),
        'p_admin_invite_code': normalizedCode,
        'p_phone': phone.trim(),
        'p_company_name': companyName.trim(),
      });
      debugPrint(
        '[register_staff_for_me] RPC response: ${_rpcResultToMap(rpcRaw)}',
      );

      final staff = await _waitForStaffProfile();
      debugPrint(
        '[register_staff_for_me] staff_users ready: '
        'user_id=${staff.userId} approved=${staff.approved}',
      );
      return staff;
    } on PostgrestException catch (e) {
      debugPrint(
        '[register_staff_for_me] RPC failed: ${e.message} '
        '(code=${e.code}, hint=${e.hint}, details=${e.details})',
      );
      throw AdminException(mapAdminPostgrestError(e));
    } on AuthException catch (e) {
      throw AdminException('인증 오류: ${e.message}');
    }
  }

  Future<StaffProfile> _waitForStaffProfile() async {
    const attempts = 12;
    const delay = Duration(milliseconds: 300);

    for (var i = 0; i < attempts; i++) {
      final staff = await _staffRepo.fetchMyProfile();
      if (staff != null) return staff;
      if (i < attempts - 1) await Future.delayed(delay);
    }

    throw const AdminException(
      '관리자 등록은 완료되었으나 staff_users 확인에 실패했습니다. '
      '잠시 후 다시 로그인해주세요.',
    );
  }

  static Map<String, dynamic> _rpcResultToMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'raw': data?.toString()};
  }

  Future<BranchStats> fetchBranchStats(String complexId) async {
    final vehicles = await supabase
        .from('vehicles')
        .select(
          'id, is_published, is_under_maintenance, insurance_expires_at',
        )
        .eq('complex_id', complexId);

    final vehicleIds =
        (vehicles as List).map((v) => v['id'].toString()).toList();

    if (vehicleIds.isEmpty) return BranchStats.empty;

    final inUseRows = await supabase
        .from('reservations')
        .select('id')
        .inFilter('vehicle_id', vehicleIds)
        .eq('status', 'in_use');

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day).toUtc();
    final dayEnd = dayStart.add(const Duration(days: 1));

    const todayReservationStatuses = [
      'confirmed',
      'in_use',
      'completed',
      'returned',
    ];
    final dayStartIso = dayStart.toIso8601String();
    final dayEndIso = dayEnd.toIso8601String();
    final todayDateFilter =
        'and(start_time.gte."$dayStartIso",start_time.lt."$dayEndIso"),'
        'and(start_at.gte."$dayStartIso",start_at.lt."$dayEndIso")';

    final todayRows = await supabase
        .from('reservations')
        .select('id')
        .inFilter('vehicle_id', vehicleIds)
        .inFilter('status', todayReservationStatuses)
        .or(todayDateFilter);

    var todaySales = 0;
    var monthSales = 0;
    try {
      final salesData = await supabase.rpc(
        'get_admin_branch_sales_stats',
        params: {'p_complex_id': complexId},
      );
      if (salesData is Map) {
        final m = Map<String, dynamic>.from(salesData);
        todaySales = (m['today_sales'] as num?)?.toInt() ?? 0;
        monthSales = (m['month_sales'] as num?)?.toInt() ?? 0;
      }
    } on PostgrestException catch (e) {
      if (!_isAdminBranchSalesStatsRpcMissing(e)) rethrow;
    }

    var available = 0;
    for (final v in vehicles) {
      if (VehicleInsuranceStatus.isResidentBookable(
        isPublished: v['is_published'] == true,
        isUnderMaintenance: v['is_under_maintenance'] == true,
        insuranceExpiresAt: v['insurance_expires_at'] == null
            ? null
            : DateTime.tryParse(v['insurance_expires_at'].toString()),
      )) {
        available++;
      }
    }

    return BranchStats(
      totalVehicles: vehicles.length,
      availableVehicles: available - (inUseRows as List).length,
      inOperation: (inUseRows).length,
      todayReservations: (todayRows as List).length,
      todaySales: todaySales,
      monthSales: monthSales,
    );
  }

  /// complex 소속 차량 중 status=in_use 예약이 걸린 vehicle_id
  Future<List<AdminVehicleDashboardCard>> fetchVehicleDashboardCards(
    String complexId,
  ) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id, model_name, car_number, created_at')
        .eq('complex_id', complexId)
        .order('created_at', ascending: true);

    final vehicleList = (vehicles as List)
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    if (vehicleList.isEmpty) return [];

    final ids = vehicleList.map((v) => v['id'].toString()).toList();

    final rows = await supabase
        .from('reservations')
        .select(
          'vehicle_id, status, start_at, start_time, end_at, end_time, '
          'rental_started_at, user_profiles(full_name)',
        )
        .inFilter('vehicle_id', ids)
        .inFilter('status', ['in_use', 'confirmed']);

    final byVehicle = <String, Map<String, dynamic>>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final vid = row['vehicle_id']?.toString();
      if (vid == null) continue;
      final existing = byVehicle[vid];
      if (existing == null) {
        byVehicle[vid] = row;
        continue;
      }
      if (existing['status'] == 'in_use') continue;
      if (row['status'] == 'in_use') {
        byVehicle[vid] = row;
      }
    }

    DateTime? parseDt(Object? v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    String? renterName(Map<String, dynamic> row) {
      final profile = row['user_profiles'];
      if (profile is Map) {
        final name = profile['full_name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
      return null;
    }

    return vehicleList.map((v) {
      final vid = v['id'].toString();
      final active = byVehicle[vid];
      if (active == null) {
        return AdminVehicleDashboardCard(
          vehicleId: vid,
          vehicleName: v['model_name']?.toString() ?? '차량',
          carNumber: v['car_number']?.toString(),
          status: AdminVehicleDashboardStatus.available,
        );
      }

      final statusRaw = active['status']?.toString();
      final isInUse = statusRaw == 'in_use';
      return AdminVehicleDashboardCard(
        vehicleId: vid,
        vehicleName: v['model_name']?.toString() ?? '차량',
        carNumber: v['car_number']?.toString(),
        status: isInUse
            ? AdminVehicleDashboardStatus.inUse
            : AdminVehicleDashboardStatus.waitingPayment,
        renterName: renterName(active),
        periodStart: isInUse
            ? parseDt(active['rental_started_at']) ??
                parseDt(active['start_at'] ?? active['start_time'])
            : parseDt(active['start_at'] ?? active['start_time']),
        periodEnd: parseDt(active['end_at'] ?? active['end_time']),
      );
    }).toList();
  }

  Future<Set<String>> fetchInUseVehicleIds(String complexId) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id')
        .eq('complex_id', complexId);
    final ids = (vehicles as List).map((v) => v['id'].toString()).toList();
    if (ids.isEmpty) return {};

    final rows = await supabase
        .from('reservations')
        .select('vehicle_id')
        .inFilter('vehicle_id', ids)
        .eq('status', 'in_use');

    return (rows as List)
        .map((r) => r['vehicle_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<List<AdminVehicleDetail>> fetchVehicles(String complexId) async {
    final complexDisplayName = await _resolveComplexDisplayName(complexId);
    final rows = await supabase
        .from('vehicles')
        .select('*, complexes(name)')
        .eq('complex_id', complexId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (r) => _vehicleDetailFromRow(
            Map<String, dynamic>.from(r),
            complexDisplayName,
          ),
        )
        .toList();
  }

  /// complexes.name 조인 + 직접 조회 + RPC 폴백 (RLS·조인 실패 대비)
  Future<String?> _resolveComplexDisplayName(String complexId) async {
    final id = complexId.trim();
    if (id.isEmpty) return _fetchMyStaffComplexNameRpc();

    try {
      final row = await supabase
          .from('complexes')
          .select('name')
          .eq('id', id)
          .maybeSingle();
      final name = row?['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    } on PostgrestException catch (e) {
      debugPrint('[AdminService] complexes select failed: ${e.message}');
    }

    return _fetchMyStaffComplexNameRpc();
  }

  Future<String?> _fetchMyStaffComplexNameRpc() async {
    try {
      final raw = await supabase.rpc('get_my_staff_complex_name');
      final name = raw?.toString().trim();
      if (name == null || name.isEmpty) return null;
      return name;
    } on PostgrestException catch (e) {
      debugPrint('[AdminService] get_my_staff_complex_name failed: ${e.message}');
      return null;
    }
  }

  AdminVehicleDetail _vehicleDetailFromRow(
    Map<String, dynamic> row,
    String? complexDisplayName,
  ) {
    final detail = AdminVehicleDetail.fromMap(row);
    final joined = detail.complexName?.trim();
    if (joined != null && joined.isNotEmpty) return detail;
    final fallback = complexDisplayName?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return detail.withComplexName(fallback);
    }
    return detail;
  }

  Future<AdminVehicleDetail> createVehicle(AdminVehicleDetail vehicle) async {
    final staffComplexId = await _requireStaffComplexId();
    final insert = vehicle.toInsertMap();
    insert['complex_id'] = staffComplexId;

    final row = await _upsertVehicleRow(insert: insert);
    final displayName = await _resolveComplexDisplayName(staffComplexId);
    return _vehicleDetailFromRow(
      Map<String, dynamic>.from(row),
      displayName,
    );
  }

  Future<AdminVehicleDetail> updateVehicle(AdminVehicleDetail vehicle) async {
    final staffComplexId = await _requireStaffComplexId();
    final update = vehicle.toUpdateMap();
    update['complex_id'] = staffComplexId;

    final row = await _upsertVehicleRow(
      update: update,
      vehicleId: vehicle.id,
    );
    final displayName = await _resolveComplexDisplayName(staffComplexId);
    return _vehicleDetailFromRow(
      Map<String, dynamic>.from(row),
      displayName,
    );
  }

  /// 노출/대기 전환
  Future<void> setVehiclePublished({
    required String vehicleId,
    required bool published,
  }) async {
    await _requireStaffComplexId();
    await supabase.from('vehicles').update({
      'is_published': published,
    }).eq('id', vehicleId);
  }

  /// 점검중 설정/해제 — maintenance_memo 포함
  Future<void> setVehicleMaintenance({
    required String vehicleId,
    required bool underMaintenance,
    String? memo,
  }) async {
    await _requireStaffComplexId();
    await supabase.from('vehicles').update({
      'is_under_maintenance': underMaintenance,
      'maintenance_memo': underMaintenance ? memo?.trim() : null,
    }).eq('id', vehicleId);
  }

  /// 차량 등록·수정 시 staff_users.complex_id 사용
  Future<String> _requireStaffComplexId() async {
    final staff = await _staffRepo.fetchMyProfile();
    final id = staff?.complexId.trim();
    if (staff == null || id == null || id.isEmpty) {
      throw const AdminException(
        '관리자 단지 정보를 찾을 수 없습니다. staff_users를 확인해주세요.',
      );
    }
    return id;
  }

  static const _businessDocumentsBucket = 'business-documents';

  static const _complexBusinessSelect =
      'id, name, business_name, business_registration_number, '
      'business_address, business_representative, business_phone, '
      'business_license_url';

  /// 본인 단지(complexes) 사업자 정보 조회
  Future<AdminComplexBusinessInfo> fetchComplexBusinessInfo() async {
    final complexId = await _requireStaffComplexId();
    final row = await supabase
        .from('complexes')
        .select(_complexBusinessSelect)
        .eq('id', complexId)
        .single();
    return AdminComplexBusinessInfo.fromMap(
      Map<String, dynamic>.from(row),
    );
  }

  /// 본인 단지(complexes) 사업자 정보 저장
  Future<AdminComplexBusinessInfo> updateComplexBusinessInfo(
    AdminComplexBusinessInfo info,
  ) async {
    final complexId = await _requireStaffComplexId();
    if (info.complexId != complexId) {
      throw const AdminException('다른 단지 정보는 수정할 수 없습니다.');
    }

    final row = await supabase
        .from('complexes')
        .update(info.toUpdateMap())
        .eq('id', complexId)
        .select(_complexBusinessSelect)
        .single();

    return AdminComplexBusinessInfo.fromMap(
      Map<String, dynamic>.from(row),
    );
  }

  /// business_license_url → 화면 표시용 signed URL (private bucket)
  Future<String?> resolveBusinessLicenseDisplayUrl(String? stored) async {
    final path = businessLicenseStoragePath(stored);
    if (path == null) return null;
    try {
      return await supabase.storage
          .from(_businessDocumentsBucket)
          .createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('[admin] business license signed url failed: $e');
      final url = stored?.trim();
      if (url != null && url.startsWith('http')) return url;
      return null;
    }
  }

  static String? businessLicenseStoragePath(String? stored) {
    final value = stored?.trim();
    if (value == null || value.isEmpty) return null;
    const marker = '/business-documents/';
    final markerIndex = value.indexOf(marker);
    if (markerIndex >= 0) {
      return value.substring(markerIndex + marker.length);
    }
    if (value.contains('://')) return null;
    return value;
  }

  /// business-documents/{complex_id}/business_license.jpg 업로드 후 public URL 반환
  Future<String> uploadBusinessLicense({
    required String complexId,
    required XFile image,
  }) async {
    final staffComplexId = await _requireStaffComplexId();
    if (staffComplexId != complexId) {
      throw const AdminException('다른 단지 사업자등록증은 업로드할 수 없습니다.');
    }

    final path = '$complexId/business_license.jpg';
    final bytes = await image.readAsBytes();
    final ext = image.path.split('.').last.toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

    try {
      if (kIsWeb) {
        await supabase.storage.from(_businessDocumentsBucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      } else {
        await supabase.storage.from(_businessDocumentsBucket).upload(
              path,
              File(image.path),
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      }
    } on StorageException catch (e) {
      throw AdminException(
        e.message.isNotEmpty
            ? e.message
            : '사업자등록증 업로드에 실패했습니다.',
      );
    }

    return supabase.storage.from(_businessDocumentsBucket).getPublicUrl(path);
  }

  Future<Map<String, dynamic>> _upsertVehicleRow({
    Map<String, dynamic>? insert,
    Map<String, dynamic>? update,
    String? vehicleId,
  }) async {
    final payloads = _vehiclePayloadVariants(insert ?? update!);

    PostgrestException? lastError;
    for (final payload in payloads) {
      try {
        if (insert != null) {
          return Map<String, dynamic>.from(
            await supabase
                .from('vehicles')
                .insert(payload)
                .select('*, complexes(name)')
                .single(),
          );
        }
        return Map<String, dynamic>.from(
          await supabase
              .from('vehicles')
              .update(payload)
              .eq('id', vehicleId!)
              .select('*, complexes(name)')
              .single(),
        );
      } on PostgrestException catch (e) {
        lastError = e;
        if (!_isRetryableVehicleColumnError(e)) rethrow;
      }
    }
    throw lastError!;
  }

  List<Map<String, dynamic>> _vehiclePayloadVariants(Map<String, dynamic> base) {
    final full = Map<String, dynamic>.from(base);

    final withoutLegacy = Map<String, dynamic>.from(base)
      ..remove('hourly_rate')
      ..remove('is_active');

    final withoutNewPrice = Map<String, dynamic>.from(base)
      ..remove('price_per_hour')
      ..remove('is_available');

    final withoutOptional = Map<String, dynamic>.from(withoutLegacy)
      ..remove('car_type')
      ..remove('fuel_type')
      ..remove('owner_name')
      ..remove('insurance_company')
      ..remove('insurance_policy_number')
      ..remove('insurance_expires_at');

    return [full, withoutLegacy, withoutNewPrice, withoutOptional];
  }

  bool _isRetryableVehicleColumnError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    return error.code == '42703' ||
        error.code == 'PGRST204' ||
        msg.contains('schema cache') ||
        msg.contains('could not find');
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await supabase.from('vehicles').delete().eq('id', vehicleId);
  }

  Future<List<AdminReservationRow>> fetchReturnInspections(
    String complexId, {
    String status = 'returned',
  }) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id')
        .eq('complex_id', complexId);
    final ids = (vehicles as List).map((v) => v['id']).toList();
    if (ids.isEmpty) return [];

    const baseSelect =
        'id, reservation_number, user_id, status, total_price, start_at, start_time, end_at, end_time, '
        'rental_started_at, returned_at, actual_end_at, updated_at, return_type, '
        'is_no_show, mileage_start, mileage_end, '
        'second_driver_name, '
        'second_driver_license, is_accident, accident_note, deductible_charged, '
        'deductible_amount, deductible_charged_at, deductible_waived, '
        'deductible_unpaid, deductible_unpaid_at, '
        'pickup_photos, return_photos, vehicles(model_name, car_number, total_mileage)';

    final orderColumn = status == 'completed' ? 'updated_at' : 'returned_at';
    final orderAscending = status != 'completed';

    Future<List> queryReservations(String select) async {
      try {
        var query = supabase
            .from('reservations')
            .select(select)
            .inFilter('vehicle_id', ids);
        if (status == 'completed') {
          // 검수 완료 탭 — completed + is_no_show 노쇼 건 명시 포함
          query = query.or(
            'and(status.eq.completed,is_no_show.eq.true),'
            'and(status.eq.completed,is_no_show.eq.false),'
            'and(status.eq.completed,is_no_show.is.null)',
          );
        } else {
          query = query.eq('status', status);
        }
        return await query.order(orderColumn, ascending: orderAscending);
      } on PostgrestException catch (e) {
        if (!_isRetryableVehicleColumnError(e)) rethrow;
        var query = supabase
            .from('reservations')
            .select(select)
            .inFilter('vehicle_id', ids);
        if (status == 'completed') {
          query = query.or(
            'and(status.eq.completed,is_no_show.eq.true),'
            'and(status.eq.completed,is_no_show.eq.false),'
            'and(status.eq.completed,is_no_show.is.null)',
          );
        } else {
          query = query.eq('status', status);
        }
        return await query.order(orderColumn, ascending: orderAscending);
      }
    }

    List rawRows;
    try {
      rawRows = await queryReservations('$baseSelect, contract_content');
    } on PostgrestException catch (e) {
      if (!_isRetryableVehicleColumnError(e)) rethrow;
      rawRows = await queryReservations(baseSelect);
    }

    final rows = rawRows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final userIds = rows
        .map((r) => r['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profileByUserId = await _fetchRenterProfilesForStaff(userIds);

    return rows.map((r) {
      final uid = r['user_id']?.toString();
      final profile = uid != null ? profileByUserId[uid] : null;
      if (profile != null) {
        r['user_profiles'] = profile;
      }
      r['renter_name'] = AdminReservationRow.resolveRenterDisplayName(
        directRenterName: r['renter_name']?.toString(),
        fullName: profile?['full_name']?.toString(),
        email: profile?['email']?.toString(),
      );
      return AdminReservationRow.fromMap(r);
    }).toList();
  }

  /// 반납 검수 등 — 임차인 full_name·이메일 (RLS + RPC fallback)
  Future<Map<String, Map<String, dynamic>>> _fetchRenterProfilesForStaff(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final result = <String, Map<String, dynamic>>{};

    try {
      final profiles = await supabase
          .from('user_profiles')
          .select('user_id, full_name, email')
          .inFilter('user_id', userIds);
      for (final profile in profiles as List) {
        final map = Map<String, dynamic>.from(profile as Map);
        final uid = map['user_id']?.toString();
        if (uid != null && uid.isNotEmpty) {
          result[uid] = map;
        }
      }
    } on PostgrestException {
      // RLS 등 — RPC로 재시도
    }

    try {
      final rpcRows = await supabase.rpc(
        'get_renter_profiles_for_staff',
        params: {'p_user_ids': userIds},
      );
      if (rpcRows is List) {
        for (final row in rpcRows) {
          if (row is! Map) continue;
          final map = Map<String, dynamic>.from(row);
          final uid = map['user_id']?.toString();
          if (uid == null || uid.isEmpty) continue;
          final existing = result[uid];
          result[uid] = {
            'user_id': uid,
            'full_name': map['full_name']?.toString() ??
                existing?['full_name']?.toString(),
            'email': map['email']?.toString() ?? existing?['email']?.toString(),
          };
        }
      }
    } on PostgrestException {
      // RPC 미배포·권한 오류 시 user_profiles 직접 조회 결과만 사용
    }

    return result;
  }

  static bool _isDisplayablePhotoUrl(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  static List<String> _normalizePhotoUrls(Iterable<String> urls) {
    return urls
        .map((url) => url.trim())
        .where(_isDisplayablePhotoUrl)
        .toList();
  }

  static DateTime? _parseRidePhotoCreatedAt(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  static ({String url, DateTime? createdAt}) _parseRidePhotoStaffRow(
    dynamic row,
  ) {
    if (row is Map) {
      return (
        url: row['photo_url']?.toString().trim() ?? '',
        createdAt: _parseRidePhotoCreatedAt(row['created_at']),
      );
    }
    return (url: row?.toString().trim() ?? '', createdAt: null);
  }

  Future<List<({String url, DateTime? createdAt})>> _fetchRidePhotoRecordsForStaff({
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
          .map(_parseRidePhotoStaffRow)
          .where((record) => record.url.isNotEmpty)
          .toList();
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('could not find the function') ||
          msg.contains('get_ride_photos_for_staff')) {
        return const [];
      }
      if (msg.contains('p_photo_type')) {
        return _fetchRidePhotoRecordsLegacyPhase(
          reservationId: reservationId,
          photoType: photoType,
        );
      }
      rethrow;
    }
  }

  Future<List<({String url, DateTime? createdAt})>>
      _fetchRidePhotoRecordsLegacyPhase({
    required String reservationId,
    required String photoType,
  }) async {
    final legacyPhase = photoType == 'before'
        ? 'pickup'
        : photoType == 'after'
            ? 'return'
            : photoType;
    try {
      final data = await supabase.rpc('get_ride_photos_for_staff', params: {
        'p_reservation_id': reservationId,
        'p_phase': legacyPhase,
      });
      if (data is! List) return const [];
      return data
          .map(_parseRidePhotoStaffRow)
          .where((record) => record.url.isNotEmpty)
          .toList();
    } on PostgrestException {
      return const [];
    }
  }

  Future<List<String>> _fetchRidePhotosForStaff({
    required String reservationId,
    required String photoType,
  }) async {
    final records = await _fetchRidePhotoRecordsForStaff(
      reservationId: reservationId,
      photoType: photoType,
    );
    return _normalizePhotoUrls(records.map((record) => record.url));
  }

  static String _normalizeReservationId(String reservationId) {
    return reservationId.trim();
  }

  /// 관리자 — 예약 계약서 본문 (없으면 generate_rental_contract_for_staff 후 재조회)
  Future<String?> ensureReservationContractForStaff(
    String reservationId,
  ) async {
    final id = _normalizeReservationId(reservationId);
    if (id.isEmpty) {
      throw const AdminException('예약번호가 없습니다.');
    }

    final complexId = await _requireStaffComplexId();
    final text = await _fetchReservationContractForStaff(
      reservationId: id,
      complexId: complexId,
    );
    if (text != null && text.isNotEmpty) return text;

    try {
      await supabase.rpc('generate_rental_contract_for_staff', params: {
        'p_reservation_id': id,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }

    return _fetchReservationContractForStaff(
      reservationId: id,
      complexId: complexId,
    );
  }

  Future<String?> _fetchReservationContractForStaff({
    required String reservationId,
    required String complexId,
  }) async {
    final id = _normalizeReservationId(reservationId);
    if (id.isEmpty) return null;

    final row = await supabase
        .from('reservations')
        .select('contract_content, vehicles(complex_id)')
        .eq('id', id)
        .maybeSingle();

    if (row == null) return null;

    final vehicleRaw = row['vehicles'];
    final vehicleComplexId = vehicleRaw is Map
        ? vehicleRaw['complex_id']?.toString()
        : null;
    if (vehicleComplexId != null && vehicleComplexId != complexId) {
      throw const AdminException('다른 단지 예약 계약서는 조회할 수 없습니다.');
    }

    final text = row['contract_content']?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  /// reservations 배열 우선, 비어 있으면 ride_photos(photo_type before/after) 폴백
  Future<({List<String> before, List<String> after})> resolveInspectionPhotos(
    AdminReservationRow row,
  ) async {
    final set = await resolveInspectionPhotoSet(row);
    return (
      before: set.before.map((e) => e.url).toList(),
      after: set.after.map((e) => e.url).toList(),
    );
  }

  /// 검수 사진 + 촬영 시각(ride_photos.created_at 우선, 없으면 대여시작/반납·검수완료 시각)
  Future<InspectionPhotoSet> resolveInspectionPhotoSet(
    AdminReservationRow row,
  ) async {
    var before = normalizeInspectionPhotoUrls(row.pickupPhotos);
    var after = normalizeInspectionPhotoUrls(row.returnPhotos);

    final beforeRecords = await _fetchRidePhotoRecordsForStaff(
      reservationId: row.id,
      photoType: 'before',
    );
    final afterRecords = await _fetchRidePhotoRecordsForStaff(
      reservationId: row.id,
      photoType: 'after',
    );

    if (before.isEmpty) {
      before = _normalizePhotoUrls(beforeRecords.map((record) => record.url));
    }
    if (after.isEmpty) {
      after = _normalizePhotoUrls(afterRecords.map((record) => record.url));
    }

    return buildInspectionPhotoSet(
      beforeUrls: before,
      afterUrls: after,
      rentalStartedAt: row.rentalStartedAt,
      returnedAt: row.returnedAt,
      actualEndAt: row.actualEndAt,
      status: row.status,
      updatedAt: row.updatedAt,
      beforeTimestampsByUrl: ridePhotoTimestampsByUrl(beforeRecords),
      afterTimestampsByUrl: ridePhotoTimestampsByUrl(afterRecords),
    );
  }

  static const int _reservationRpcPageSize = 500;

  Future<List<Map<String, dynamic>>> _fetchRpcAllPages(
    String fn, {
    Map<String, dynamic>? params,
  }) async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final data = await supabase.rpc(
        fn,
        params: {
          ...?params,
          'p_limit': _reservationRpcPageSize,
          'p_offset': offset,
        },
      );
      if (data == null) break;

      final batch = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(batch);

      if (batch.length < _reservationRpcPageSize) break;
      offset += _reservationRpcPageSize;
    }

    return all;
  }

  /// RPC에 reservation_number가 없을 때(레거시 RPC) 표시용 번호 보강
  Future<void> _enrichAdminReservationRowsWithNumbers(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;

    final needsEnrich = rows.any((r) {
      final existing = r['reservation_number']?.toString().trim();
      return existing == null || existing.isEmpty;
    });
    if (!needsEnrich) return;

    final ids = rows
        .map((r) => r['reservation_id'] ?? r['id'])
        .map((v) => v?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final fetched = await supabase
          .from('reservations')
          .select('id, reservation_number')
          .inFilter('id', ids);
      final byId = <String, String>{};
      for (final raw in fetched as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id']?.toString();
        final number = m['reservation_number']?.toString().trim();
        if (id != null && number != null && number.isNotEmpty) {
          byId[id] = number;
        }
      }
      for (final r in rows) {
        final existing = r['reservation_number']?.toString().trim();
        if (existing != null && existing.isNotEmpty) continue;
        final id = (r['reservation_id'] ?? r['id'])?.toString();
        final number = id != null ? byId[id] : null;
        if (number != null) {
          r['reservation_number'] = number;
        }
      }
    } on PostgrestException {
      // RLS 등 — 레거시 #id 표시 유지
    }
  }

  Future<List<Map<String, dynamic>>> getAdminReservationsWithConflict() async {
    try {
      final rows =
          await _fetchRpcAllPages('get_admin_reservations_with_conflict');
      await _enrichAdminReservationRowsWithNumbers(rows);
      return rows;
    } on PostgrestException catch (e) {
      if (_isReservationRpcPaginationUnsupported(e)) {
        try {
          final data =
              await supabase.rpc('get_admin_reservations_with_conflict');
          if (data == null) return [];
          final rows = List<Map<String, dynamic>>.from(data as List);
          await _enrichAdminReservationRowsWithNumbers(rows);
          return rows;
        } on PostgrestException catch (fallback) {
          throw AdminException(mapAdminPostgrestError(fallback));
        }
      }
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  bool _isReservationRpcPaginationUnsupported(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST202' ||
        msg.contains('p_limit') ||
        msg.contains('could not find the function');
  }

  Future<int> fetchConflictRiskCount() async {
    final rows = await getAdminReservationsWithConflict();
    return countBackToBackConflicts(rows);
  }

  Future<List<Map<String, dynamic>>> getAdminCompletedReservations() async {
    try {
      final rows =
          await _fetchRpcAllPages('get_admin_completed_reservations');
      await _enrichAdminReservationRowsWithNumbers(rows);
      return rows;
    } on PostgrestException catch (e) {
      if (_isReservationRpcPaginationUnsupported(e)) {
        try {
          final data = await supabase.rpc('get_admin_completed_reservations');
          if (data == null) return [];
          final rows = List<Map<String, dynamic>>.from(data as List);
          await _enrichAdminReservationRowsWithNumbers(rows);
          return rows;
        } on PostgrestException catch (fallback) {
          throw AdminException(mapAdminPostgrestError(fallback));
        }
      }
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<AdminReservationTimelineData> fetchReservationTimeline({
    required int year,
    required int month,
  }) async {
    final complexId = await _requireStaffComplexId();
    final vehicles = await fetchVehicles(complexId);

    try {
      final data = await supabase.rpc(
        'get_admin_reservation_timeline',
        params: {'p_year': year, 'p_month': month},
      );
      final rows = data is List
          ? data
              .whereType<Map>()
              .map((e) => AdminTimelineReservation.fromMap(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : <AdminTimelineReservation>[];

      return AdminReservationTimelineData(
        vehicles: vehicles,
        reservations: rows,
      );
    } on PostgrestException catch (e) {
      if (_isTimelineRpcMissing(e)) {
        return AdminReservationTimelineData(
          vehicles: vehicles,
          reservations: const [],
        );
      }
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  bool _isTimelineRpcMissing(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST202' ||
        msg.contains('get_admin_reservation_timeline') ||
        msg.contains('could not find the function');
  }

  Future<void> forceCompleteReservation(String reservationId) async {
    try {
      await supabase.rpc('force_complete_reservation_for_staff', params: {
        'p_reservation_id': reservationId,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<void> forceCancelReservation(String reservationId) async {
    try {
      await supabase.rpc('cancel_reservation_for_staff', params: {
        'p_reservation_id': reservationId,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  /// in_use 예약 → returned (반납 검수 화면)
  Future<void> forceReturnReservation(String reservationId) async {
    try {
      await supabase.rpc('force_return_reservation_for_staff', params: {
        'p_reservation_id': reservationId,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  /// CS 강제결제취소 — Toss 환불 + 예약/결제 취소
  Future<void> forcePaymentCancelReservation(String reservationId) async {
    final response = await supabase.functions.invoke(
      'admin-force-payment-cancel',
      body: {'reservationId': reservationId},
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map
          ? data['error']?.toString() ?? '강제결제취소에 실패했습니다.'
          : '강제결제취소에 실패했습니다.';
      throw AdminException(message);
    }
  }

  Future<List<AdminReservationRow>> fetchOperatingReservations(
    String complexId,
  ) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id, model_name, car_number, parking_location, last_latitude, last_longitude, last_location_updated_at')
        .eq('complex_id', complexId);
    final ids = (vehicles as List).map((v) => v['id']).toList();
    if (ids.isEmpty) return [];

    const baseSelect =
        'id, user_id, reservation_number, status, total_price, start_at, start_time, '
        'end_at, end_time, rental_started_at, '
        'vehicles(model_name, car_number, parking_location, last_latitude, last_longitude, last_location_updated_at)';

    List<dynamic> rows;
    try {
      rows = await supabase
          .from('reservations')
          .select('$baseSelect, user_profiles!left(full_name, name, email)')
          .inFilter('vehicle_id', ids)
          .eq('status', 'in_use')
          .order('rental_started_at', ascending: false);
    } on PostgrestException {
      rows = await supabase
          .from('reservations')
          .select(baseSelect)
          .inFilter('vehicle_id', ids)
          .eq('status', 'in_use')
          .order('rental_started_at', ascending: false);
    }

    final list = rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final userIds = list
        .map((r) => r['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profileByUserId = await _fetchRenterProfilesForStaff(userIds);

    return list.map((r) {
      final uid = r['user_id']?.toString();
      final embedded = r['user_profiles'];
      Map<String, dynamic>? profile;
      if (embedded is Map) {
        profile = Map<String, dynamic>.from(embedded);
      }
      final fallback = uid != null ? profileByUserId[uid] : null;
      if (fallback != null) {
        profile = {
          ...?profile,
          'full_name': fallback['full_name'] ?? profile?['full_name'],
          'name': fallback['name'] ?? profile?['name'],
          'email': fallback['email'] ?? profile?['email'],
        };
      }
      if (profile != null) {
        r['user_profiles'] = profile;
      }
      return AdminReservationRow.fromMap(r);
    }).toList();
  }

  Future<SalesSummary> fetchSalesSummary(
    String complexId, {
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final targetYear = year ?? now.year;
    final targetMonth = month ?? now.month;

    try {
      final data = await supabase.rpc(
        'get_admin_sales_summary',
        params: {
          'p_complex_id': complexId,
          'p_year': targetYear,
          'p_month': targetMonth,
        },
      );
      if (data is Map) {
        return SalesSummary.fromRpc(
          Map<String, dynamic>.from(data),
          year: targetYear,
          month: targetMonth,
        );
      }
    } on PostgrestException catch (e) {
      if (!_isAdminSalesSummaryRpcMissing(e)) rethrow;
    }

    return SalesSummary(
      totalAmount: 0,
      reservationCount: 0,
      rows: const [],
      monthHours: SalesSummary.monthHoursFor(
        year: targetYear,
        month: targetMonth,
      ),
    );
  }

  Future<List<VehicleSalesRentalItem>> fetchVehicleSalesRentals({
    required String complexId,
    required int year,
    required int month,
    required String vehicleName,
  }) async {
    try {
      final data = await supabase.rpc(
        'get_admin_vehicle_sales_rentals',
        params: {
          'p_complex_id': complexId,
          'p_year': year,
          'p_month': month,
          'p_vehicle_name': vehicleName,
        },
      );
      if (data is List) {
        return data
            .map(
              (e) => VehicleSalesRentalItem.fromRpc(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } on PostgrestException catch (e) {
      if (!_isAdminVehicleSalesRentalsRpcMissing(e)) rethrow;
    }
    return const [];
  }

  bool _isAdminVehicleSalesRentalsRpcMissing(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST202' ||
        msg.contains('get_admin_vehicle_sales_rentals') ||
        msg.contains('could not find the function');
  }

  Future<SuperAdminSettlementSheet> fetchSettlementSheet({
    int? year,
    int? month,
  }) async {
    final data = await supabase.rpc(
      'get_admin_settlement_sheet',
      params: {
        if (year != null) 'p_year': year,
        if (month != null) 'p_month': month,
      },
    );
    if (data is Map) {
      return SuperAdminSettlementSheet.fromRpc(data);
    }
    return const SuperAdminSettlementSheet();
  }

  /// 단지관리자 정산 요청 — Edge Function (푸시·앱내 알림 포함)
  Future<void> requestSettlement({
    required int year,
    required int month,
  }) async {
    final response = await supabase.functions.invoke(
      'settlement-request',
      body: {'year': year, 'month': month},
    );

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map
          ? data['error']?.toString() ?? '정산 요청에 실패했습니다.'
          : '정산 요청에 실패했습니다.';
      throw AdminException(message);
    }
  }

  bool _isAdminSalesSummaryRpcMissing(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST202' ||
        msg.contains('get_admin_sales_summary') ||
        msg.contains('could not find the function');
  }

  bool _isAdminBranchSalesStatsRpcMissing(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST202' ||
        msg.contains('get_admin_branch_sales_stats') ||
        msg.contains('could not find the function');
  }

  Future<List<LicenseReviewItem>> fetchLicenseReviews() async {
    final rows = await supabase.rpc('list_license_reviews_for_staff');
    return (rows as List)
        .map(
          (e) => LicenseReviewItem.fromMap(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<List<ResidentReviewItem>> fetchResidentReviews() async {
    try {
      final rows = await supabase.rpc('list_resident_reviews_for_staff');
      return (rows as List)
          .map(
            (e) => ResidentReviewItem.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<List<AdminCustomer>> fetchCustomers() async {
    try {
      final rows = await supabase.rpc('get_admin_customers_for_staff');
      return (rows as List)
          .map((r) => AdminCustomer.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<List<AdminCustomerReservation>> fetchCustomerReservations(
    String userId,
  ) async {
    try {
      final rows = await supabase.rpc(
        'get_admin_customer_reservations',
        params: {'p_user_id': userId},
      );
      return (rows as List)
          .map(
            (r) => AdminCustomerReservation.fromMap(
              Map<String, dynamic>.from(r),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<void> setCustomerBlacklist({
    required String userId,
    required bool blacklisted,
  }) async {
    try {
      await supabase.rpc('set_admin_user_blacklist', params: {
        'p_user_id': userId,
        'p_blacklisted': blacklisted,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<List<VehicleMaintenanceRecord>> fetchVehicleMaintenanceHistory(
    String vehicleId,
  ) async {
    try {
      final rows = await supabase.rpc(
        'get_vehicle_maintenance_history_for_staff',
        params: {'p_vehicle_id': int.parse(vehicleId)},
      );
      return (rows as List)
          .map(
            (r) => VehicleMaintenanceRecord.fromMap(
              Map<String, dynamic>.from(r),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<void> insertVehicleMaintenance({
    required String vehicleId,
    required VehicleMaintenanceType type,
    String? description,
    int cost = 0,
    int? mileage,
  }) async {
    try {
      await supabase.rpc('insert_vehicle_maintenance_for_staff', params: {
        'p_vehicle_id': int.parse(vehicleId),
        'p_maintenance_type': type.dbValue,
        'p_description': description,
        'p_cost': cost,
        'p_mileage': mileage,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<void> reviewLicense({
    required String userId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      await supabase.rpc('review_license_for_staff', params: {
        'p_user_id': userId,
        'p_approved': approved,
        'p_rejection_reason': rejectionReason,
      });
      final push = PushNotificationService.instance;
      if (approved) {
        await push.customerLicenseApproved(userId);
      } else {
        await push.customerLicenseRejected(
          userId,
          reason: rejectionReason?.trim().isNotEmpty == true
              ? rejectionReason!.trim()
              : '면허 정보 확인 불가',
        );
      }
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  /// 입주민 승인/거절 — RPC 후 관리자 세션으로 고객 푸시 (예약확정과 동일 패턴)
  Future<void> reviewResident({
    required String userId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      await supabase.rpc('review_resident_for_staff', params: {
        'p_user_id': userId,
        'p_approved': approved,
        'p_rejection_reason': rejectionReason,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }

    final push = PushNotificationService.instance;
    if (approved) {
      await push.customerResidentApproved(userId);
    } else {
      await push.customerResidentRejected(
        userId,
        reason: rejectionReason?.trim().isNotEmpty == true
            ? rejectionReason!.trim()
            : '입주민 인증 정보 확인 불가',
      );
    }
  }

  /// 사고 예약 면책금 — 고객 빌링키 자동결제 (Edge Function)
  Future<int> chargeReservationDeductible(String reservationId) async {
    final response = await supabase.functions.invoke(
      'billing-deductible-charge',
      body: {'reservationId': reservationId},
    );

    final data = response.data;
    if (response.status != 200) {
      final message = _deductibleChargeErrorMessage(data);
      throw AdminException(message);
    }
    if (data is Map) {
      return (data['amount'] as num?)?.toInt() ??
          AdminReservationRow.defaultDeductibleAmount;
    }
    return AdminReservationRow.defaultDeductibleAmount;
  }

  String _deductibleChargeErrorMessage(Object? data) {
    if (data is Map) {
      final code = data['code']?.toString();
      if (code == 'billing_key_missing') {
        return '고객에게 등록된 결제카드가 없습니다.';
      }
      if (code == 'deductible_already_charged') {
        return '이미 면책금이 청구되었습니다.';
      }
      if (code == 'deductible_waived') {
        return '면책금이 면제된 예약입니다.';
      }
      if (code == 'not_accident_reservation') {
        return '사고 예약만 면책금을 청구할 수 있습니다.';
      }
      if (code == 'billing_charge_failed') {
        return '결제에 실패했습니다. 1시간 간격으로 최대 3회 자동 재시도됩니다. 카드 한도·잔액을 확인해주세요.';
      }
      final err = data['error']?.toString();
      if (err != null && err.isNotEmpty) return err;
    }
    return '면책금 청구에 실패했습니다.';
  }

  Future<void> waiveReservationDeductible(String reservationId) async {
    try {
      await supabase.rpc(
        'waive_reservation_deductible_for_staff',
        params: {'p_reservation_id': reservationId},
      );
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  /// 반납 검수 완료 — RPC 후 관리자 세션으로 고객 푸시 (예약확정과 동일 패턴)
  Future<void> completeReturnInspection(String reservationId) async {
    try {
      await supabase.rpc('complete_return_inspection_for_staff', params: {
        'p_reservation_id': reservationId,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }

    String? userId;
    try {
      final row = await supabase
          .from('reservations')
          .select('user_id')
          .eq('id', reservationId)
          .maybeSingle();
      userId = row?['user_id']?.toString();
    } catch (e, st) {
      debugPrint(
        '[admin] return inspection user lookup failed (non-fatal): $e\n$st',
      );
    }

    if (userId == null || userId.isEmpty) return;

    await PushNotificationService.instance.customerReturnInspectionComplete(
      userId: userId,
      reservationId: reservationId,
    );
  }

  /// 공지사항 목록 (본인 단지 + 전체 공지)
  Future<List<Notice>> fetchNotices(String complexId) async {
    final rows = await supabase
        .from('notices')
        .select('id, complex_id, title, content, is_active, created_at')
        .or('complex_id.is.null,complex_id.eq.$complexId')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Notice.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Notice> createNotice({
    required String complexId,
    required String title,
    required String content,
    bool isGlobal = false,
    bool isActive = true,
  }) async {
    final row = await supabase
        .from('notices')
        .insert({
          'complex_id': isGlobal ? null : complexId,
          'title': title.trim(),
          'content': content.trim(),
          'is_active': isActive,
        })
        .select('id, complex_id, title, content, is_active, created_at')
        .single();

    return Notice.fromMap(Map<String, dynamic>.from(row));
  }

  Future<Notice> updateNotice({
    required String noticeId,
    required String title,
    required String content,
    required bool isActive,
    bool isGlobal = false,
    required String complexId,
  }) async {
    final row = await supabase
        .from('notices')
        .update({
          'complex_id': isGlobal ? null : complexId,
          'title': title.trim(),
          'content': content.trim(),
          'is_active': isActive,
        })
        .eq('id', noticeId)
        .select('id, complex_id, title, content, is_active, created_at')
        .single();

    return Notice.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteNotice(String noticeId) async {
    await supabase.from('notices').delete().eq('id', noticeId);
  }
}

String mapAdminPostgrestError(PostgrestException error) {
  final msg = error.message.toLowerCase();
  final details = error.details?.toString().toLowerCase() ?? '';

  if (msg.contains('not_authenticated')) {
    return '로그인 후에만 관리자 가입이 가능합니다. 이메일 인증을 확인해주세요.';
  }
  if (msg.contains('invalid_display_name')) {
    return '관리자 이름을 입력해주세요.';
  }
  if (msg.contains('admin_invite_not_found') ||
      msg.contains('invalid_admin_invite_code')) {
    return AdminService.invalidInviteCodeMessage;
  }
  if (msg.contains('invalid_phone')) {
    return '전화번호를 입력해주세요.';
  }
  if (msg.contains('invalid_company_name')) {
    return '업체명을 입력해주세요.';
  }
  if (msg.contains('staff_already_registered')) {
    return '이미 등록된 관리자 계정입니다.';
  }
  if (msg.contains('schema_missing') || msg.contains('column_missing')) {
    return 'DB 스키마가 준비되지 않았습니다.\n'
        'Supabase에서 create_admin_staff.sql 및 최신 migration을 적용해주세요.\n'
        '(${error.message})';
  }
  if (msg.contains('permission denied') && msg.contains('auth')) {
    return '관리자 가입 RPC 권한 오류입니다.\n'
        'migration 20260604160000_fix_register_staff_for_me.sql 을 적용해주세요.';
  }
  if (msg.contains('register_staff_for_me') &&
      (msg.contains('could not find') || msg.contains('pgrst202'))) {
    return '관리자 RPC가 설치되지 않았습니다.\n'
        'Supabase에서 create_admin_staff.sql 및 migration을 실행해주세요.';
  }
  if (details.isNotEmpty && !msg.contains(error.message.toLowerCase())) {
    return '${error.message}\n$details';
  }
  if (msg.contains('row-level security') || msg.contains('policy')) {
    return '관리자 승인이 필요합니다.\n'
        'Supabase에서 approve_staff.sql 로 approved = true 후 이용해주세요.';
  }
  if (msg.contains('reservation_not_found')) {
    return '예약을 찾을 수 없습니다.';
  }
  if (msg.contains('invalid_status')) {
    return '검수할 수 없는 예약 상태입니다.';
  }
  if (msg.contains('not_eligible_for_force_complete')) {
    return '강제 완료 대상이 아닙니다. (24시간 경과·상태 확인)';
  }
  if (msg.contains('not_no_show_suspect')) {
    return '노쇼의심 예약만 강제 반납할 수 있습니다.';
  }
  if (msg.contains('forbidden')) {
    return '관리자 권한이 필요합니다.';
  }
  if (msg.contains('resident_not_found')) {
    return '해당 입주민을 찾을 수 없습니다.';
  }
  if (msg.contains('invalid_maintenance_type')) {
    return '정비 유형이 올바르지 않습니다.';
  }
  if (msg.contains('vehicle_not_found')) {
    return '차량을 찾을 수 없습니다.';
  }
  if (msg.contains('deductible_already_charged')) {
    return '이미 면책금이 청구되었습니다.';
  }
  if (msg.contains('deductible_already_waived')) {
    return '이미 면책금이 면제되었습니다.';
  }
  if (msg.contains('not_accident_reservation')) {
    return '사고 예약만 면책금을 처리할 수 있습니다.';
  }
  return error.message;
}

String friendlyAdminError(Object error) {
  if (error is AdminException) return error.message;
  if (error is PostgrestException) return mapAdminPostgrestError(error);
  return error.toString();
}
