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

  Future<void> registerStaff({
    required String displayName,
    required String adminInviteCode,
  }) async {
    try {
      await supabase.rpc('register_staff_for_me', params: {
        'p_display_name': displayName.trim(),
        'p_admin_invite_code': adminInviteCode.trim(),
      });
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }
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

  Future<List<AdminVehicleDetail>> fetchVehicles(String complexId) async {
    final rows = await supabase
        .from('vehicles')
        .select('*')
        .eq('complex_id', complexId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => AdminVehicleDetail.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<AdminVehicleDetail> createVehicle(AdminVehicleDetail vehicle) async {
    final row = await _upsertVehicleRow(
      insert: vehicle.toInsertMap(),
    );
    return AdminVehicleDetail.fromMap(Map<String, dynamic>.from(row));
  }

  Future<AdminVehicleDetail> updateVehicle(AdminVehicleDetail vehicle) async {
    final row = await _upsertVehicleRow(
      update: vehicle.toUpdateMap(),
      vehicleId: vehicle.id,
    );
    return AdminVehicleDetail.fromMap(Map<String, dynamic>.from(row));
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
                .select('*')
                .single(),
          );
        }
        return Map<String, dynamic>.from(
          await supabase
              .from('vehicles')
              .update(payload)
              .eq('id', vehicleId!)
              .select('*')
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
  if (msg.contains('admin_invite_not_found')) {
    return '관리자 초대코드가 올바르지 않습니다.';
  }
  if (msg.contains('staff_already_registered')) {
    return '이미 등록된 관리자 계정입니다.';
  }
  if (msg.contains('register_staff_for_me') &&
      msg.contains('could not find')) {
    return '관리자 RPC가 설치되지 않았습니다.\n'
        'Supabase에서 create_admin_staff.sql 을 실행해주세요.';
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
