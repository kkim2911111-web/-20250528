import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/license_review_item.dart';
import '../models/staff_profile.dart';
import '../repositories/staff_repository.dart';
import '../supabase_client.dart';

class AdminException implements Exception {
  final String message;
  const AdminException(this.message);
  @override
  String toString() => message;
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
        .select('id, is_available')
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

    final todayRows = await supabase
        .from('reservations')
        .select('id')
        .inFilter('vehicle_id', vehicleIds)
        .gte('start_time', dayStart.toIso8601String())
        .lt('start_time', dayEnd.toIso8601String());

    final monthStart = DateTime(now.year, now.month, 1).toUtc();
    final salesRows = await supabase
        .from('reservations')
        .select('total_price')
        .inFilter('vehicle_id', vehicleIds)
        .inFilter('status', ['confirmed', 'in_use', 'returned', 'completed'])
        .gte('start_time', monthStart.toIso8601String());

    var available = 0;
    for (final v in vehicles) {
      if (v['is_available'] == true) available++;
    }

    var monthSales = 0;
    for (final r in salesRows as List) {
      monthSales += (r['total_price'] as num?)?.toInt() ?? 0;
    }

    return BranchStats(
      totalVehicles: vehicles.length,
      availableVehicles: available - (inUseRows as List).length,
      inOperation: (inUseRows).length,
      todayReservations: (todayRows as List).length,
      monthSales: monthSales,
    );
  }

  /// complex 소속 차량 중 status=in_use 예약이 걸린 vehicle_id
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

  static const _complexBusinessSelect =
      'id, name, business_name, business_registration_number, '
      'business_address, business_representative, business_phone';

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
      ..remove('vehicle_type')
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
    String complexId,
  ) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id')
        .eq('complex_id', complexId);
    final ids = (vehicles as List).map((v) => v['id']).toList();
    if (ids.isEmpty) return [];

    final rows = await supabase
        .from('reservations')
        .select(
          'id, status, total_price, start_at, start_time, end_at, end_time, '
          'is_accident, accident_note, vehicles(model_name, car_number)',
        )
        .inFilter('vehicle_id', ids)
        .eq('status', 'returned')
        .order('returned_at', ascending: false);

    return (rows as List)
        .map((r) => AdminReservationRow.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> completeReturnInspection(String reservationId) async {
    try {
      await supabase.rpc('complete_return_inspection_for_staff', params: {
        'p_reservation_id': reservationId,
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
  }

  Future<List<Map<String, dynamic>>> getAdminReservationsWithConflict() async {
    try {
      final data = await supabase.rpc('get_admin_reservations_with_conflict');
      if (data == null) return [];
      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
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

    final rows = await supabase
        .from('reservations')
        .select(
          'id, status, total_price, start_at, start_time, end_at, end_time, '
          'vehicles(model_name, car_number, parking_location, last_latitude, last_longitude, last_location_updated_at)',
        )
        .inFilter('vehicle_id', ids)
        .eq('status', 'in_use')
        .order('rental_started_at', ascending: false);

    return (rows as List)
        .map((r) => AdminReservationRow.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<SalesSummary> fetchSalesSummary(String complexId) async {
    final vehicles = await supabase
        .from('vehicles')
        .select('id, model_name')
        .eq('complex_id', complexId);
    if ((vehicles as List).isEmpty) {
      return const SalesSummary(totalAmount: 0, reservationCount: 0, rows: []);
    }

    final ids = vehicles.map((v) => v['id']).toList();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toUtc();

    final rows = await supabase
        .from('reservations')
        .select('total_price, vehicle_id, vehicles(model_name)')
        .inFilter('vehicle_id', ids)
        .inFilter('status', ['confirmed', 'in_use', 'returned', 'completed'])
        .gte('start_time', monthStart.toIso8601String());

    final byVehicle = <String, SalesRow>{};
    var total = 0;
    var count = 0;

    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row);
      final price = (map['total_price'] as num?)?.toInt() ?? 0;
      final vehicleRaw = map['vehicles'];
      final name = vehicleRaw is Map
          ? vehicleRaw['model_name']?.toString() ??
              vehicleRaw['name']?.toString() ??
              '차량'
          : '차량';
      total += price;
      count++;
      final existing = byVehicle[name];
      byVehicle[name] = SalesRow(
        vehicleName: name,
        amount: (existing?.amount ?? 0) + price,
        count: (existing?.count ?? 0) + 1,
      );
    }

    return SalesSummary(
      totalAmount: total,
      reservationCount: count,
      rows: byVehicle.values.toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
    );
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
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
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
  return error.message;
}

String friendlyAdminError(Object error) {
  if (error is AdminException) return error.message;
  if (error is PostgrestException) return mapAdminPostgrestError(error);
  return error.toString();
}
