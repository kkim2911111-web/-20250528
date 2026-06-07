import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/rental_extension_result.dart';
import '../models/fuel_level.dart';
import '../models/grouped_reservations.dart';
import '../constants/payment_order_status.dart';
import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../supabase_client.dart';
import 'payment_service.dart';
import 'reservation_refresh_bus.dart';
import 'push_notification_service.dart';
import 'reservation_service.dart';

class RentalException implements Exception {
  final String message;
  const RentalException(this.message);

  @override
  String toString() => message;
}

class RentalService {
  static const bucketName = 'rental-photos';

  /// PostgREST * 가 DB에 없는 updated_at 을 포함할 때 오류 방지
  static const _selectFull = '''
id,user_id,vehicle_id,start_at,end_at,start_time,end_time,total_price,status,
payment_key,order_id,payment_status,rental_started_at,returned_at,actual_end_at,
return_type,is_no_show,early_return_confirmed_at,
pickup_photos,return_photos,mileage_start,mileage_end,
fuel_level_start,fuel_level_end,is_accident,accident_note,door_unlocked,
contract_content,second_driver_name,second_driver_license
''';

  static const _selectCore =
      'id,user_id,vehicle_id,start_at,end_at,start_time,end_time,total_price,status';

  static const _selectBare =
      'id,user_id,vehicle_id,start_time,end_time,total_price,status';

  final _paymentService = PaymentService();

  /// 결제·취소 후 목록 캐시 무효화 + UI 새로고침
  static void signalListRefresh() {
    clearQueryCache();
    ReservationRefreshBus.instance.notifyChanged();
  }

  Future<void> _autoCompleteExpired() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.rpc('auto_complete_expired_reservations_for_me');
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('could not find the function') ||
          msg.contains('auto_complete_expired_reservations_for_me')) {
        return;
      }
      debugPrint('[rental] auto_complete_expired skipped: ${e.message}');
    } catch (e) {
      debugPrint('[rental] auto_complete_expired skipped: $e');
    }
  }

  static const _selectMinimal =
      'id,user_id,vehicle_id,start_at,end_at,start_time,end_time,total_price,status,payment_key,payment_status,order_id';

  /// 성공한 select/order 조합 캐시 — 400 반복 요청 방지
  static String? _cachedSelect;
  static String? _cachedOrderCol;

  /// 결제·취소 후 캐시 무효화 (스키마 변경·신규 예약 반영)
  static void clearQueryCache() {
    _cachedSelect = null;
    _cachedOrderCol = null;
  }

  Future<List<dynamic>> _queryReservationRows(String userId) async {
    if (_cachedSelect != null) {
      try {
        return await _fetchRows(
          userId,
          select: _cachedSelect!,
          orderCol: _cachedOrderCol,
        );
      } on PostgrestException {
        _cachedSelect = null;
        _cachedOrderCol = null;
      }
    }

    const attempts = <(String, String?)>[
      (_selectBare, null),
      (_selectBare, 'start_time'),
      (_selectCore, 'start_time'),
      (_selectMinimal, 'start_time'),
      (_selectFull, 'start_time'),
      (_selectCore, 'start_at'),
      (_selectMinimal, 'start_at'),
      (_selectFull, 'start_at'),
    ];

    PostgrestException? lastError;
    for (final (select, orderCol) in attempts) {
      try {
        final rows = await _fetchRows(
          userId,
          select: select,
          orderCol: orderCol,
        );
        _cachedSelect = select;
        _cachedOrderCol = orderCol;
        return rows;
      } on PostgrestException catch (e) {
        lastError = e;
        if (!_isRetryableFetchError(e)) rethrow;
      }
    }
    throw RentalException(_friendlyFetchError(lastError!));
  }

  Future<List<dynamic>> _fetchRows(
    String userId, {
    required String select,
    String? orderCol,
  }) async {
    final base =
        supabase.from('reservations').select(select).eq('user_id', userId);
    final rows = orderCol == null
        ? await base
        : await base.order(orderCol, ascending: false);
    debugPrint(
      '[rental] reservations select ok userId=$userId '
      'cols=${select.split(',').length} order=$orderCol count=${rows.length}',
    );
    return rows;
  }

  bool _isRetryableFetchError(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('does not exist') ||
        msg.contains('could not find') ||
        msg.contains('column') ||
        msg.contains('order') ||
        e.code == '42703' ||
        e.code == 'PGRST204' ||
        e.code == 'PGRST103';
  }

  Object _coerceVehicleId(String id) {
    final parsed = int.tryParse(id);
    return parsed ?? id;
  }

  Future<List<Reservation>> _fetchCancelledReservationsFromPaymentOrders(
    String userId,
  ) async {
    try {
      final rows = await supabase
          .from('payment_orders')
          .select(PaymentOrderColumns.selectDetail)
          .eq('user_id', userId)
          .eq('status', PaymentOrderStatus.cancelled)
          .order('updated_at', ascending: false);

      return (rows as List)
          .map((row) {
            if (row is! Map) return null;
            return _reservationFromCancelledPaymentOrder(
              Map<String, dynamic>.from(row),
              userId,
            );
          })
          .whereType<Reservation>()
          .toList();
    } on PostgrestException catch (e) {
      debugPrint(
        '[rental] cancelled payment_orders fetch skipped: ${e.message}',
      );
      return [];
    }
  }

  Reservation _reservationFromCancelledPaymentOrder(
    Map<String, dynamic> row,
    String userId,
  ) {
    final vehicleId = row['vehicle_id']?.toString() ?? '';
    final vehicleName = row['vehicle_name']?.toString();
    Vehicle? vehicle;
    if (vehicleName != null && vehicleName.trim().isNotEmpty) {
      vehicle = Vehicle(
        id: vehicleId.isNotEmpty ? vehicleId : '0',
        complexId: '',
        name: vehicleName.trim(),
        vehicleType: '기타',
        pricePerHour: 0,
        isAvailable: false,
      );
    }

    final reservationId = row['reservation_id']?.toString();
    final orderId = row['order_id']?.toString();

    DateTime? parseTs(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v.toLocal();
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    return Reservation(
      id: (reservationId != null && reservationId.isNotEmpty)
          ? reservationId
          : (orderId ?? ''),
      userId: userId,
      vehicleId: vehicleId,
      startAt: parseTs(row['start_time']),
      endAt: parseTs(row['end_time']),
      totalPrice: (row['total_price'] as num?)?.toInt() ?? 0,
      status: 'cancelled',
      orderId: orderId,
      cancelledAt: parseTs(row['updated_at']),
      vehicle: vehicle,
    );
  }

  Future<List<Reservation>> fetchMyReservations({bool forceRefresh = false}) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    if (forceRefresh) {
      clearQueryCache();
    }

    await _autoCompleteExpired();

    List<dynamic> rows;
    try {
      rows = await _queryReservationRows(user.id);
    } on PostgrestException catch (e) {
      debugPrint('[rental] fetchMyReservations error: ${e.message} code=${e.code}');
      clearQueryCache();
      rethrow;
    }

    if (rows.isEmpty) {
      debugPrint('[rental] fetchMyReservations — 0 rows (RLS 또는 미저장 확인)');
    }

    return _attachVehicles(
      rows
          .map((row) {
            if (row is! Map) return null;
            return Reservation.fromMap(Map<String, dynamic>.from(row));
          })
          .whereType<Reservation>()
          .toList(),
    );
  }

  Future<List<Reservation>> _attachVehicles(List<Reservation> list) async {
    final missingIds = list
        .where((r) => r.vehicle == null && r.vehicleId.isNotEmpty)
        .map((r) => r.vehicleId)
        .toSet()
        .toList();
    if (missingIds.isEmpty) return list;

    try {
      final ids = missingIds.map(_coerceVehicleId).toList();
      final vehicleRows = await supabase
          .from('vehicles')
          .select('*')
          .inFilter('id', ids);

      final byId = <String, Vehicle>{};
      for (final row in vehicleRows as List) {
        final map = Map<String, dynamic>.from(row);
        final v = Vehicle.fromMap(map);
        byId[v.id] = v;
      }

      return list
          .map(
            (r) => r.vehicle != null
                ? r
                : Reservation(
                    id: r.id,
                    userId: r.userId,
                    vehicleId: r.vehicleId,
                    startAt: r.startAt,
                    endAt: r.endAt,
                    totalPrice: r.totalPrice,
                    status: r.status,
                    paymentKey: r.paymentKey,
                    paymentStatus: r.paymentStatus,
                    orderId: r.orderId,
                    rentalStartedAt: r.rentalStartedAt,
                    returnedAt: r.returnedAt,
                    actualEndAt: r.actualEndAt,
                    pickupPhotos: r.pickupPhotos,
                    returnPhotos: r.returnPhotos,
                    mileageStart: r.mileageStart,
                    mileageEnd: r.mileageEnd,
                    fuelLevelStart: r.fuelLevelStart,
                    fuelLevelEnd: r.fuelLevelEnd,
                    isAccident: r.isAccident,
                    accidentNote: r.accidentNote,
                    doorUnlocked: r.doorUnlocked,
                    contractContent: r.contractContent,
                    vehicle: byId[r.vehicleId],
                  ),
          )
          .toList();
    } catch (_) {
      return list;
    }
  }

  /// 스마트키 문열림/닫힘
  Future<bool> setDoorLock({
    required String reservationId,
    required bool unlocked,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    try {
      final data = await supabase.rpc('set_door_lock_for_me', params: {
        'p_reservation_id': reservationId,
        'p_unlocked': unlocked,
      });
      final map = _asMap(data);
      return map['doorUnlocked'] == true;
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('could not find the function')) {
        return _setDoorLockDirect(
          reservationId: reservationId,
          userId: user.id,
          unlocked: unlocked,
        );
      }
      throw RentalException(friendlyRentalError(e));
    }
  }

  Future<bool> _setDoorLockDirect({
    required String reservationId,
    required String userId,
    required bool unlocked,
  }) async {
    try {
      await supabase
          .from('reservations')
          .update({'door_unlocked': unlocked})
          .eq('id', reservationId)
          .eq('user_id', userId);
      return unlocked;
    } on PostgrestException catch (e) {
      if (e.message.contains('door_unlocked')) {
        throw const RentalException(
          'door_unlocked 컬럼이 없습니다.\n'
          'Supabase에서 fix_reservations_schema.sql 을 실행해주세요.',
        );
      }
      rethrow;
    }
  }

  String _friendlyFetchError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    if (msg.contains('updated_at')) {
      return 'reservations 테이블에 updated_at 컬럼이 없습니다.\n'
          'Supabase SQL Editor에서 fix_reservations_schema.sql 을 실행해주세요.';
    }
    if (msg.contains('permission') || msg.contains('policy')) {
      return '예약 조회 권한이 없습니다. 입주민 승인 상태를 확인해주세요.';
    }
    return error.message;
  }

  /// 스마트키 — 대여 중(in_use) 예약만
  Future<List<Reservation>> fetchSmartKeyReservations() async {
    final all = await fetchMyReservations();
    final list = all.where((r) => r.isSmartKeyEligible).toList();
    list.sort(_compareSmartKey);
    return list;
  }

  /// 내 예약 — 운행중 / 대기 / (완료→이용내역)
  Future<GroupedReservations> fetchGroupedReservations({
    bool historyOnly = false,
    bool forceRefresh = false,
  }) async {
    final all = await fetchMyReservations(forceRefresh: forceRefresh);
    final operating = <Reservation>[];
    final waiting = <Reservation>[];
    final finished = <Reservation>[];

    for (final r in all) {
      if (historyOnly) {
        if (r.isInUsageHistory) {
          finished.add(r);
        }
        continue;
      }

      // 내 예약 — 취소·완료·시간 경과(미운행) 제외 → 이용내역으로
      if (r.isInUsageHistory) {
        continue;
      }

      if (r.isOperating || r.status == 'in_use') {
        operating.add(r);
      } else if (r.isWaiting) {
        waiting.add(r);
      } else if (r.isActiveStatus && !r.isUsageTimeExpired) {
        waiting.add(r);
      }
    }

    operating.sort(_compareOperatingForDisplay);
    waiting.sort(_compareByStartAsc);
    finished.sort(_compareByStartDesc);

    debugPrint(
      '[rental] grouped historyOnly=$historyOnly '
      'operating=${operating.length} waiting=${waiting.length} '
      'finished=${finished.length}',
    );

    if (historyOnly) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final fromOrders = await _fetchCancelledReservationsFromPaymentOrders(
          user.id,
        );
        final existingIds = finished.map((r) => r.id).toSet();
        final existingOrderIds = finished
            .map((r) => r.orderId?.trim())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
        for (final r in fromOrders) {
          if (existingIds.contains(r.id)) continue;
          final oid = r.orderId?.trim();
          if (oid != null && oid.isNotEmpty && existingOrderIds.contains(oid)) {
            continue;
          }
          finished.add(r);
        }
        finished.sort(_compareByStartDesc);
      }

      final pricing = await ReservationService()
          .fetchPaymentPricingForReservations(finished);
      return GroupedReservations(
        operating: const [],
        waiting: const [],
        finished: finished,
        paymentPricing: pricing,
      );
    }

    final pricing = await ReservationService()
        .fetchPaymentPricingForReservations([...operating, ...waiting]);
    return GroupedReservations(
      operating: operating,
      waiting: waiting,
      finished: const [],
      paymentPricing: pricing,
    );
  }

  static int _compareByStartAsc(Reservation a, Reservation b) =>
      a.sortByStart.compareTo(b.sortByStart);

  static int _compareOperatingForDisplay(Reservation a, Reservation b) {
    if (a.status == 'in_use' && b.status != 'in_use') return -1;
    if (b.status == 'in_use' && a.status != 'in_use') return 1;
    return _compareByStartAsc(a, b);
  }

  static int _compareByStartDesc(Reservation a, Reservation b) =>
      b.sortByStart.compareTo(a.sortByStart);

  static int _compareSmartKey(Reservation a, Reservation b) {
    if (a.isOperating && !b.isOperating) return -1;
    if (b.isOperating && !a.isOperating) return 1;
    return _compareByStartAsc(a, b);
  }

  Future<Reservation> fetchReservation(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    PostgrestException? lastError;
    for (final select in ['$_selectFull, vehicles(*)', '$_selectMinimal, vehicles(*)']) {
      try {
        final row = await supabase
            .from('reservations')
            .select(select)
            .eq('id', _reservationIdFilter(reservationId))
            .eq('user_id', user.id)
            .maybeSingle();

        if (row == null) {
          throw const RentalException('예약 정보를 찾을 수 없습니다.');
        }

        final list = await _attachVehicles([
          Reservation.fromMap(Map<String, dynamic>.from(row)),
        ]);
        return list.first;
      } on PostgrestException catch (e) {
        lastError = e;
        if (!_isRetryableFetchError(e)) rethrow;
      }
    }
    throw RentalException(_friendlyFetchError(lastError!));
  }

  Future<List<String>> uploadPhotos({
    required String reservationId,
    required String phase,
    required List<Uint8List> photos,
    int minPhotos = 1,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    if (photos.length < minPhotos) {
      throw RentalException('사진을 최소 ${minPhotos}장 등록해주세요.');
    }
    if (photos.length > 10) {
      throw const RentalException('사진은 최대 10장까지 등록할 수 있습니다.');
    }

    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final path =
          '${user.id}/$reservationId/$phase/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      await supabase.storage.from(bucketName).uploadBinary(
            path,
            photos[i],
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      urls.add(supabase.storage.from(bucketName).getPublicUrl(path));
    }
    return urls;
  }

  Future<void> _insertRidePhotos({
    required String reservationId,
    required String userId,
    required String phase,
    required List<String> photoUrls,
  }) async {
    final photoType = phase == 'pickup' ? 'before' : 'after';
    try {
      await supabase
          .from('ride_photos')
          .delete()
          .eq('reservation_id', reservationId)
          .eq('user_id', userId)
          .eq('phase', phase);

      final rows = photoUrls.asMap().entries.map((entry) {
        return {
          'reservation_id': reservationId,
          'user_id': userId,
          'phase': phase,
          'photo_type': photoType,
          'photo_url': entry.value,
          'photo_order': entry.key,
        };
      }).toList();

      if (rows.isNotEmpty) {
        await supabase.from('ride_photos').insert(rows);
      }
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return;
      debugPrint('[rental] ride_photos insert skipped: ${e.message}');
    }
  }

  static bool reservationIdIsBigint(String reservationId) {
    return RegExp(r'^\d+$').hasMatch(reservationId.trim());
  }

  Object _reservationIdFilter(String reservationId) {
    if (reservationIdIsBigint(reservationId)) {
      return int.parse(reservationId.trim());
    }
    return reservationId;
  }

  /// 이용내역 — 계약서 본문 (없으면 null)
  Future<String?> fetchContractContent(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    try {
      final row = await supabase
          .from('reservations')
          .select('contract_content')
          .eq('id', _reservationIdFilter(reservationId))
          .eq('user_id', user.id)
          .maybeSingle();
      final text = row?['contract_content']?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') return null;
      rethrow;
    }
  }

  /// 계약서 RPC 생성 후 본문 반환 (이미 있으면 RPC 생략)
  Future<String?> ensureContractContent(String reservationId) async {
    final cached = await fetchContractContent(reservationId);
    if (cached != null && cached.isNotEmpty) return cached;

    await generateRentalContract(reservationId);
    return fetchContractContent(reservationId);
  }

  Future<void> generateRentalContract(String reservationId) async {
    final id = int.tryParse(reservationId.trim());
    if (id == null) {
      throw RentalException('유효하지 않은 예약번호입니다.');
    }
    await supabase.rpc('generate_rental_contract', params: {
      'p_reservation_id': id,
    });
  }

  Future<Map<String, dynamic>> startRental({
    required String reservationId,
    required List<Uint8List> photos,
  }) async {
    final photoUrls = await uploadPhotos(
      reservationId: reservationId,
      phase: 'pickup',
      photos: photos,
      minPhotos: 6,
    );

    PostgrestException? rpcError;
    try {
      final data = await supabase.rpc('start_rental_for_me', params: {
        'p_reservation_id': reservationId,
        'p_pickup_photos': photoUrls,
        'p_mileage_start': null,
        'p_fuel_level_start': null,
      });
      await _assertReservationInUse(reservationId);
      RentalService.signalListRefresh();
      final result = _asMap(data);
      try {
        final reservation = await fetchReservation(reservationId);
        await _notifyRentalStarted(reservation);
      } catch (_) {}
      return result;
    } on PostgrestException catch (e) {
      rpcError = e;
      if (!_shouldFallbackStartRental(e)) {
        throw RentalException(friendlyStartRentalError(e));
      }
    }

    try {
      final result = await _startRentalDirect(
        reservationId: reservationId,
        photoUrls: photoUrls,
      );
      await _assertReservationInUse(reservationId);
      RentalService.signalListRefresh();
      try {
        final reservation = await fetchReservation(reservationId);
        await _notifyRentalStarted(reservation);
      } catch (_) {}
      return result;
    } on PostgrestException catch (e) {
      throw RentalException(friendlyStartRentalError(e));
    } on RentalException {
      rethrow;
    } catch (e) {
      final rpcMsg = rpcError != null
          ? friendlyStartRentalError(rpcError!)
          : e.toString();
      throw RentalException('$rpcMsg\n($e)');
    }
  }

  bool _shouldFallbackStartRental(PostgrestException error) {
    final msg = _postgrestErrorText(error);
    return msg.contains('invalid input syntax for type uuid') ||
        msg.contains('invalid_reservation_id') ||
        msg.contains('reservation_not_found') ||
        msg.contains('could not find the function') ||
        msg.contains('start_rental_for_me') ||
        msg.contains('does not exist') ||
        msg.contains('42703') ||
        msg.contains('schema cache') ||
        msg.contains('reservations_status_check') ||
        msg.contains('check constraint');
  }

  String _postgrestErrorText(PostgrestException error) {
    return '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
        .toLowerCase();
  }

  bool _isMissingColumnError(PostgrestException error) {
    final msg = _postgrestErrorText(error);
    return msg.contains('does not exist') ||
        msg.contains('42703') ||
        msg.contains('schema cache');
  }

  Future<void> _persistRentalStart({
    required String reservationId,
    required String userId,
    required String now,
    required List<String> photoUrls,
  }) async {
    final idFilter = _reservationIdFilter(reservationId);
    final payloads = <Map<String, dynamic>>[
      {
        'status': 'in_use',
        'rental_started_at': now,
        'pickup_photos': photoUrls,
      },
      {
        'status': 'in_use',
        'rental_started_at': now,
      },
      {
        'status': 'in_use',
      },
    ];

    PostgrestException? lastError;
    for (final payload in payloads) {
      try {
        final row = await supabase
            .from('reservations')
            .update(payload)
            .eq('id', idFilter)
            .eq('user_id', userId)
            .select('status')
            .maybeSingle();
        if (row != null && row['status']?.toString() == 'in_use') {
          return;
        }
      } on PostgrestException catch (e) {
        lastError = e;
        if (!_isMissingColumnError(e)) {
          throw RentalException(friendlyStartRentalError(e));
        }
      }
    }

    throw RentalException(friendlyStartRentalError(lastError!));
  }

  Future<Map<String, dynamic>> _startRentalDirect({
    required String reservationId,
    required List<String> photoUrls,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final row = await _fetchReservationRow(reservationId, user.id);
    if (row == null) {
      throw const RentalException('예약 정보를 찾을 수 없습니다.');
    }

    final reservation = Reservation.fromMap(Map<String, dynamic>.from(row));
    if (!reservation.canStartRental) {
      throw RentalException(
        '대여를 시작할 수 없는 예약 상태입니다. (${reservation.statusLabel})',
      );
    }

    final nowDt = DateTime.now();
    final start = reservation.startAt;
    final end = reservation.endAt;
    if (start != null &&
        nowDt.isBefore(start.subtract(Reservation.rentalStartLeadTime))) {
      throw const RentalException(RentalStartMessages.tooEarly);
    }
    if (end != null && nowDt.isAfter(end)) {
      throw const RentalException('예약 시간이 지나 대여를 시작할 수 없습니다.');
    }

    final now = nowDt.toUtc().toIso8601String();
    await _persistRentalStart(
      reservationId: reservationId,
      userId: user.id,
      now: now,
      photoUrls: photoUrls,
    );
    await _insertRidePhotos(
      reservationId: reservationId,
      userId: user.id,
      phase: 'pickup',
      photoUrls: photoUrls,
    );

    return {
      'reservationId': reservationId,
      'status': 'in_use',
      'rentalStartedAt': now,
    };
  }

  Future<void> _assertReservationInUse(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final row = await supabase
        .from('reservations')
        .select('status')
        .eq('id', _reservationIdFilter(reservationId))
        .eq('user_id', user.id)
        .maybeSingle();

    if (row != null && row['status']?.toString() == 'in_use') {
      return;
    }

    throw const RentalException(
      '대여 시작이 저장되지 않았습니다.\n'
      'status가 in_use로 변경되지 않았습니다. 다시 시도해주세요.',
    );
  }

  Future<void> _notifyReservationCancelled(Reservation reservation) async {
    final user = supabase.auth.currentUser;
    final vehicle = reservation.vehicle;
    if (user == null || vehicle == null || vehicle.complexId.isEmpty) return;

    final push = PushNotificationService.instance;
    await push.customerReservationCancelled(
      userId: user.id,
      reservationId: reservation.id,
      vehicleName: vehicle.name,
    );
    await push.staffReservationCancelled(
      complexId: vehicle.complexId,
      reservationId: reservation.id,
      vehicleName: vehicle.name,
    );
  }

  Future<void> _notifyRentalStarted(Reservation reservation) async {
    final vehicle = reservation.vehicle;
    if (vehicle == null || vehicle.complexId.isEmpty) return;
    final profile = await supabase
        .from('user_profiles')
        .select('full_name')
        .eq('user_id', reservation.userId)
        .maybeSingle();
    final renterName = profile?['full_name']?.toString();
    await PushNotificationService.instance.staffRentalStarted(
      complexId: vehicle.complexId,
      reservationId: reservation.id,
      vehicleName: vehicle.name,
      renterName: renterName,
    );
    await PushNotificationService.instance.customerRentalStarted(
      userId: reservation.userId,
      reservationId: reservation.id,
      endAt: reservation.endAt?.toUtc().toIso8601String(),
    );
  }

  Future<void> _notifyReturnCompleted(Reservation reservation) async {
    final vehicle = reservation.vehicle;
    if (vehicle == null || vehicle.complexId.isEmpty) return;
    await PushNotificationService.instance.staffReturnCompleted(
      complexId: vehicle.complexId,
      reservationId: reservation.id,
      vehicleName: vehicle.name,
    );
  }

  Future<Map<String, dynamic>> cancelReservation(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    Reservation? cancelledReservation;
    try {
      cancelledReservation = await fetchReservation(reservationId);
    } catch (_) {}

    if (cancelledReservation == null) {
      RentalService.signalListRefresh();
      return {
        'reservationId': reservationId,
        'alreadyCancelled': true,
      };
    }

    Object? lastError;
    try {
      final result = await _paymentService.cancelConfirmedReservation(
        reservationId: reservationId,
      );
      await _assertReservationCancelled(reservationId);
      await _runPostCancelRestoreRpcs(reservationId);
      RentalService.signalListRefresh();
      return result;
    } catch (e) {
      if (isReservationAlreadyGoneError(e)) {
        RentalService.signalListRefresh();
        return {
          'reservationId': reservationId,
          'alreadyCancelled': true,
        };
      }
      lastError = e;
      final message = friendlyPaymentError(e);
      if (!_shouldFallbackCancel(message)) {
        throw RentalException(message);
      }
    }

    try {
      final result = await _cancelReservationDirect(reservationId);
      if (cancelledReservation != null) {
        await _notifyReservationCancelled(cancelledReservation!);
      }
      return result;
    } catch (e) {
      if (isReservationAlreadyGoneError(e)) {
        RentalService.signalListRefresh();
        return {
          'reservationId': reservationId,
          'alreadyCancelled': true,
        };
      }
      if (e is RentalException) rethrow;
      final fallback = friendlyPaymentError(e);
      throw RentalException(
        '$fallback\n(이전 오류: ${friendlyPaymentError(lastError)})',
      );
    }
  }

  bool _shouldFallbackCancel(String message) {
    if (isReservationAlreadyGoneError(message)) return false;
    final lower = message.toLowerCase();
    return lower.contains('invalid input syntax for type uuid') ||
        lower.contains('invalid_reservation_id') ||
        lower.contains('cancel_reservation_for_me') ||
        lower.contains('could not find the function') ||
        lower.contains('could not find') ||
        lower.contains('failed to fetch') ||
        lower.contains('payment-cancel') ||
        lower.contains('예약 취소가 저장되지 않았습니다') ||
        lower.contains('check constraint') ||
        lower.contains('reservations_status_check') ||
        lower.contains('v.name') ||
        lower.contains('does not exist') ||
        lower.contains('42703');
  }

  Future<void> _assertReservationCancelled(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final row = await supabase
        .from('reservations')
        .select('status')
        .eq('id', reservationId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null || row['status']?.toString() == 'cancelled') {
      return;
    }

    throw const RentalException(
      '예약 취소가 저장되지 않았습니다.\n'
      'Supabase SQL Editor에서 cancel_reservation_rpc.sql 을 실행해주세요.',
    );
  }

  Future<Map<String, dynamic>?> _fetchReservationRow(
    String reservationId,
    String userId,
  ) async {
    const selects = [
      'id, user_id, vehicle_id, start_at, start_time, end_at, end_time, '
          'total_price, status, payment_key, payment_status, order_id',
      _selectCore,
      _selectBare,
    ];
    for (final select in selects) {
      try {
        final row = await supabase
            .from('reservations')
            .select(select)
            .eq('id', _reservationIdFilter(reservationId))
            .eq('user_id', userId)
            .maybeSingle();
        if (row != null) {
          return Map<String, dynamic>.from(row);
        }
        return null;
      } on PostgrestException catch (e) {
        if (!_isRetryableFetchError(e)) rethrow;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _cancelReservationDirect(
    String reservationId,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final row = await _fetchReservationRow(reservationId, user.id);

    if (row == null) {
      throw const RentalException('예약 정보를 찾을 수 없습니다.');
    }

    final reservation = Reservation.fromMap(Map<String, dynamic>.from(row));
    if (!reservation.canCancel) {
      if (reservation.isCancelBlocked) {
        throw RentalException(ReservationCancelMessages.tooLate);
      }
      throw const RentalException('취소할 수 없는 예약 상태입니다.');
    }

    try {
      final data = await supabase.rpc('cancel_reservation_for_me', params: {
        'p_reservation_id': reservationId,
      });
      await _assertReservationCancelled(reservationId);
      await _runPostCancelRestoreRpcs(reservationId);
      RentalService.signalListRefresh();
      return _asMap(data);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (_isRpcCancelFallbackError(msg)) {
        return _cancelReservationByDelete(
          reservationId: reservationId,
          userId: user.id,
          orderId: reservation.orderId,
        );
      }
      throw RentalException(friendlyRentalError(e));
    }
  }

  bool _isRpcCancelFallbackError(String msg) {
    return msg.contains('could not find the function') ||
        msg.contains('invalid input syntax for type uuid') ||
        msg.contains('v.name') ||
        msg.contains('does not exist') ||
        msg.contains('42703');
  }

  Future<Map<String, dynamic>> _cancelReservationByDelete({
    required String reservationId,
    required String userId,
    String? orderId,
  }) async {
    await supabase
        .from('reservations')
        .delete()
        .eq('id', reservationId)
        .eq('user_id', userId);

    await _assertReservationCancelled(reservationId);
    await _runPostCancelRestoreRpcs(reservationId);

    if (orderId != null && orderId.isNotEmpty) {
      try {
        await supabase
            .from('payment_orders')
            .update(PaymentOrderPayload.markCancelled())
            .eq('order_id', orderId)
            .eq('user_id', userId);
      } catch (_) {}
    }

    RentalService.signalListRefresh();
    return {'reservationId': reservationId, 'deleted': true};
  }

  /// 예약 취소 후 쿠폰·포인트 복구 (DB가 스킵 처리).
  Future<void> _runPostCancelRestoreRpcs(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[cancel] skip restore RPCs — not logged in');
      return;
    }

    final params = {
      'p_user_id': user.id,
      'p_reservation_id': reservationId,
    };

    try {
      final data = await supabase.rpc('restore_user_coupon', params: params);
      debugPrint('[cancel] restore_user_coupon ok: $data');
    } catch (e, st) {
      debugPrint('[cancel] restore_user_coupon failed: $e\n$st');
    }

    try {
      await supabase.rpc('restore_used_points', params: {
        'p_user_id': supabase.auth.currentUser!.id,
        'p_reservation_id': reservationId.toString(),
      });
      debugPrint('[cancel] restore_used_points ok');
    } catch (e) {
      debugPrint('[cancel] restore_used_points failed: $e');
    }
  }

  Future<RentalExtensionCheckResult> checkRentalExtension({
    required String reservationId,
    int extensionHours = 1,
  }) async {
    try {
      final data = await supabase.rpc('check_rental_extension_for_me', params: {
        'p_reservation_id': reservationId,
        'p_extension_hours': extensionHours,
      });
      return RentalExtensionCheckResult.fromMap(_parseExtensionRpcMap(data));
    } on PostgrestException catch (e) {
      throw RentalException(friendlyRentalError(e));
    }
  }

  /// 빌링키 결제 후 연장 적용 (Edge Function)
  Future<Map<String, dynamic>> payAndApplyRentalExtension({
    required String reservationId,
    int extensionHours = 1,
  }) async {
    try {
      final data = await PaymentService().payRentalExtensionWithBilling(
        reservationId: reservationId,
        extensionHours: extensionHours,
      );
      final map = _asMap(data);
      RentalService.signalListRefresh();
      final result = map['result'];
      if (result is Map) return _asMap(result);
      return map;
    } catch (e) {
      if (e is RentalException) rethrow;
      throw RentalException(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  int _extensionAmountFromResponse(Map<String, dynamic> data) {
    final top = data['addedPrice'] ?? data['added_price'];
    if (top is num) return top.toInt();
    final result = data['result'];
    if (result is Map) {
      final nested = Map<String, dynamic>.from(result);
      final nestedAmount = nested['addedPrice'] ?? nested['added_price'];
      if (nestedAmount is num) return nestedAmount.toInt();
    }
    return 0;
  }

  /// 연장 결제 완료 포인트 적립 — 실패해도 연장 흐름 유지
  Future<void> tryGrantExtensionPoints({
    required String reservationId,
    required int amount,
  }) async {
    final user = supabase.auth.currentUser;
    debugPrint(
      '[extension/points] tryGrantExtensionPoints start: '
      'reservationId=$reservationId, p_amount=$amount, userId=${user?.id}',
    );

    if (user == null) {
      debugPrint('[extension/points] skip — not logged in');
      return;
    }
    if (reservationId.isEmpty) {
      debugPrint('[extension/points] skip — empty reservationId');
      return;
    }
    if (amount <= 0) {
      debugPrint('[extension/points] skip — p_amount is 0 or negative');
      return;
    }

    try {
      final data = await supabase.rpc('grant_extension_points', params: {
        'p_user_id': user.id,
        'p_reservation_id': reservationId,
        'p_amount': amount,
      });
      debugPrint('[extension/points] grant_extension_points ok: $data');
    } on PostgrestException catch (e) {
      debugPrint(
        '[extension/points] grant_extension_points PostgrestException: '
        '${e.code} ${e.message}',
      );
    } catch (e, st) {
      debugPrint('[extension/points] grant_extension_points error: $e\n$st');
    }
  }

  Future<Map<String, dynamic>> applyRentalExtension({
    required String reservationId,
    int extensionHours = 1,
  }) async {
    return payAndApplyRentalExtension(
      reservationId: reservationId,
      extensionHours: extensionHours,
    );
  }

  Future<Map<String, dynamic>> logEmergencyConsultation({
    String? reservationId,
    String requestType = 'extension_blocked',
    String? reasonCode,
    Map<String, dynamic>? context,
  }) async {
    try {
      final data =
          await supabase.rpc('log_emergency_consultation_for_me', params: {
        'p_reservation_id': reservationId,
        'p_request_type': requestType,
        'p_reason_code': reasonCode,
        'p_context': context ?? {},
      });
      return _asMap(data);
    } on PostgrestException catch (e) {
      throw RentalException(friendlyRentalError(e));
    }
  }

  Future<Map<String, dynamic>> completeReturn({
    required String reservationId,
    required List<Uint8List> photos,
    required int mileageEnd,
    required FuelLevel fuelLevelEnd,
    required bool isAccident,
    String? accidentNote,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final photoUrls = await uploadPhotos(
      reservationId: reservationId,
      phase: 'return',
      photos: photos,
    );

    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      final data = await supabase.rpc('complete_rental_for_me', params: {
        'p_reservation_id': reservationId,
        'p_return_photos': photoUrls,
        'p_mileage_end': mileageEnd,
        'p_fuel_level_end': fuelLevelEnd.value,
        'p_is_accident': isAccident,
        'p_accident_note': accidentNote,
      });
      await _assertReservationReturnCompleted(reservationId);
      await _insertRidePhotos(
        reservationId: reservationId,
        userId: user.id,
        phase: 'return',
        photoUrls: photoUrls,
      );
      await _grantReservationPointsAfterReturn(reservationId);
      RentalService.signalListRefresh();
      final result = _asMap(data);
      try {
        final reservation = await fetchReservation(reservationId);
        await _notifyReturnCompleted(reservation);
      } catch (_) {}
      return result;
    } on PostgrestException catch (e) {
      if (_shouldFallbackCompleteRental(e)) {
        await _persistReturnComplete(
          reservationId: reservationId,
          userId: user.id,
          nowIso: nowIso,
          photoUrls: photoUrls,
          mileageEnd: mileageEnd,
          fuelLevelEnd: fuelLevelEnd.value,
          isAccident: isAccident,
          accidentNote: accidentNote,
        );
        await _insertRidePhotos(
          reservationId: reservationId,
          userId: user.id,
          phase: 'return',
          photoUrls: photoUrls,
        );
        await _grantReservationPointsAfterReturn(reservationId);
        RentalService.signalListRefresh();
        try {
          final reservation = await fetchReservation(reservationId);
          await _notifyReturnCompleted(reservation);
        } catch (_) {}
        return {
          'reservationId': reservationId,
          'status': 'returned',
          'returnedAt': nowIso,
          'actualEndAt': nowIso,
        };
      }
      throw RentalException(friendlyRentalError(e));
    }
  }

  bool _shouldFallbackCompleteRental(PostgrestException error) {
    final msg = _postgrestErrorText(error);
    return msg.contains('could not find the function') ||
        msg.contains('complete_rental_for_me') ||
        msg.contains('schema cache');
  }

  Future<void> _persistReturnComplete({
    required String reservationId,
    required String userId,
    required String nowIso,
    required List<String> photoUrls,
    required int mileageEnd,
    required String fuelLevelEnd,
    required bool isAccident,
    String? accidentNote,
  }) async {
    final idFilter = _reservationIdFilter(reservationId);
    final note = isAccident ? accidentNote?.trim() : null;
    final payloads = <Map<String, dynamic>>[
      {
        'status': 'returned',
        'returned_at': nowIso,
        'actual_end_at': nowIso,
        'return_type': 'manual',
        'return_photos': photoUrls,
        'mileage_end': mileageEnd,
        'fuel_level_end': fuelLevelEnd,
        'is_accident': isAccident,
        'accident_note': note,
      },
      {
        'status': 'returned',
        'returned_at': nowIso,
        'actual_end_at': nowIso,
        'return_photos': photoUrls,
        'mileage_end': mileageEnd,
        'fuel_level_end': fuelLevelEnd,
      },
      {
        'status': 'returned',
        'returned_at': nowIso,
      },
    ];

    PostgrestException? lastError;
    for (final payload in payloads) {
      try {
        final row = await supabase
            .from('reservations')
            .update(payload)
            .eq('id', idFilter)
            .eq('user_id', userId)
            .eq('status', 'in_use')
            .select('status')
            .maybeSingle();
        if (row != null &&
            _isReturnCompletedStatus(row['status']?.toString())) {
          return;
        }
      } on PostgrestException catch (e) {
        lastError = e;
        if (!_isMissingColumnError(e)) {
          throw RentalException(friendlyRentalError(e));
        }
      }
    }

    if (lastError != null) {
      throw RentalException(friendlyRentalError(lastError));
    }
    throw const RentalException(
      '반납 상태(returned)가 저장되지 않았습니다. 다시 시도해주세요.',
    );
  }

  bool _isReturnCompletedStatus(String? status) {
    final s = status?.trim().toLowerCase();
    return s == 'completed' || s == 'returned';
  }

  Future<void> _grantReservationPointsAfterReturn(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.rpc('grant_reservation_points', params: {
        'p_user_id': user.id,
        'p_reservation_id': reservationId.toString(),
        'p_amount': 0,
      });
      debugPrint('[rental/points] grant_reservation_points ok');
    } catch (e) {
      debugPrint('[rental/points] grant_reservation_points failed: $e');
    }
  }

  Future<void> _assertReservationReturnCompleted(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final row = await supabase
        .from('reservations')
        .select('status')
        .eq('id', _reservationIdFilter(reservationId))
        .eq('user_id', user.id)
        .maybeSingle();

    final status = row?['status']?.toString();
    if (_isReturnCompletedStatus(status)) return;

    if (status == 'in_use') {
      throw const RentalException(
        '반납은 처리되었으나 status가 in_use로 남아 있습니다.\n'
        'Supabase에서 complete_rental_for_me 마이그레이션(20260619120000)을 실행해주세요.',
      );
    }

    throw RentalException(
      '반납 상태가 저장되지 않았습니다. (현재: ${status ?? 'unknown'})',
    );
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Map<String, dynamic> _parseExtensionRpcMap(Object? data) {
    final map = _asMap(data);
    if (map.containsKey('eligible') || map.containsKey('reason')) {
      return map;
    }
    for (final key in ['data', 'result']) {
      final nested = map[key];
      if (nested is Map) {
        final inner = _asMap(nested);
        if (inner.containsKey('eligible') || inner.containsKey('reason')) {
          return inner;
        }
      }
    }
    return map;
  }
}

String friendlyRentalError(PostgrestException error) {
  final msg = error.message.toLowerCase();

  if (msg.contains('photos_required')) {
    return '차량 사진 등록이 필요합니다. (문열림: 대여 전 사진 10장)';
  }
  if (msg.contains('set_door_lock_for_me') &&
      msg.contains('could not find')) {
    return '스마트키 RPC가 설치되지 않았습니다.\n'
        'Supabase에서 smart_key_door_rpc.sql 을 실행해주세요.';
  }
  if (msg.contains('too_many_photos')) {
    return '사진은 최대 10장까지 등록할 수 있습니다.';
  }
  if (msg.contains('invalid_mileage') || msg.contains('mileage_decreased')) {
    return '주행거리를 올바르게 입력해주세요. (반납 시 대여 시보다 작을 수 없습니다)';
  }
  if (msg.contains('invalid_fuel_level')) {
    return '주유 상태를 선택해주세요.';
  }
  if (msg.contains('accident_note_required')) {
    return '사고 발생 시 내용을 입력해주세요.';
  }
  if (msg.contains('reservation_not_found')) {
    return '예약 정보를 찾을 수 없습니다.';
  }
  if (msg.contains('invalid_status')) {
    return '현재 상태에서는 진행할 수 없습니다. 대여 시작(in_use) 후 반납해주세요.';
  }
  if (msg.contains('invalid_end_time')) {
    return '예약 종료 시간 정보가 없습니다.';
  }
  if (msg.contains('invalid_extension_hours')) {
    return '연장 시간을 올바르게 입력해주세요.';
  }
  if (msg.contains('payment_required')) {
    return '연장 전 결제가 필요합니다. 앱을 최신 버전으로 업데이트 후 다시 시도해주세요.';
  }
  if (msg.contains('extension_not_eligible') ||
      msg.contains('next_reservation_exists')) {
    return '다음 예약이 있어 연장할 수 없습니다.';
  }
  if (msg.contains('too_early') && msg.contains('extension')) {
    return '대여 종료 1시간 전부터 연장 신청이 가능합니다.';
  }
  if (msg.contains('too_early')) {
    return RentalStartMessages.tooEarly;
  }
  if (msg.contains('expired')) {
    return '예약 시간이 지나 대여를 시작할 수 없습니다.';
  }
  if (msg.contains('cancel_too_late')) {
    return ReservationCancelMessages.tooLate;
  }
  if (msg.contains('auto_complete_expired_reservations_for_me') &&
      msg.contains('could not find')) {
    return '만료 예약 자동 반납 RPC가 없습니다.\n'
        'Supabase에서 auto_return_expired_reservations.sql 을 실행해주세요.';
  }
  if (msg.contains('v.name') || msg.contains('does not exist')) {
    return '예약 취소 RPC 오류입니다.\n'
        'Supabase SQL Editor에서 cancel_reservation_rpc.sql 을 다시 실행해주세요.';
  }
  if (msg.contains('reservations_status_check') ||
      msg.contains('check constraint')) {
    return '예약 취소 상태(cancelled)가 DB에 등록되지 않았습니다.\n'
        'Supabase SQL Editor에서 cancel_reservation_rpc.sql 을 실행해주세요.';
  }
  if (msg.contains('could not find the function')) {
    if (msg.contains('cancel_reservation_for_me')) {
      return '예약 취소 RPC가 설치되지 않았습니다.\nSupabase에서 cancel_reservation_rpc.sql 을 실행해주세요.';
    }
    if (msg.contains('start_rental_for_me')) {
      return '대여 시작 RPC가 설치되지 않았습니다.\nSupabase에서 fix_rental_rpcs_bigint.sql 을 실행해주세요.';
    }
    if (msg.contains('complete_rental_for_me')) {
      return '반납 RPC가 설치되지 않았습니다.\n'
          'Supabase에서 supabase/migrations/20260619120000_fix_return_inspection_status_flow.sql 을 실행해주세요.';
    }
    if (msg.contains('check_rental_extension_for_me') ||
        msg.contains('apply_rental_extension_for_me')) {
      return '대여 연장 RPC가 설치되지 않았습니다.\nSupabase에서 rental_extension.sql 을 실행해주세요.';
    }
    return '대여 RPC가 설치되지 않았습니다.\nSupabase에서 rental_rpcs.sql 을 실행해주세요.';
  }
  if (msg.contains('invalid input syntax for type uuid') &&
      msg.contains('reservation')) {
    return '예약 ID 형식 오류입니다.\nSupabase에서 fix_rental_rpcs_bigint.sql 을 실행해주세요.';
  }
  if (msg.contains('row-level security') || msg.contains('policy')) {
    return '저장 권한이 없습니다. Storage 버킷 정책을 확인해주세요.';
  }

  return error.message;
}

String friendlyStartRentalError(PostgrestException error) {
  final msg = error.message.toLowerCase();

  if (msg.contains('photos_required')) {
    return '차량 사진을 최소 6장 이상 등록해주세요.';
  }
  if (msg.contains('too_many_photos')) {
    return '사진은 최대 10장까지 등록할 수 있습니다.';
  }
  if (msg.contains('invalid_mileage')) {
    return '주행거리를 올바르게 입력해주세요.';
  }
  if (msg.contains('invalid_fuel_level')) {
    return '주유 상태를 선택해주세요.';
  }
  if (msg.contains('reservation_not_found')) {
    return '예약 정보를 찾을 수 없습니다.';
  }
  if (msg.contains('invalid_status')) {
    return '대여를 시작할 수 없는 예약 상태입니다.';
  }
  if (msg.contains('too_early')) {
    return RentalStartMessages.tooEarly;
  }
  if (msg.contains('expired')) {
    return '예약 시간이 지나 대여를 시작할 수 없습니다.';
  }
  if (msg.contains('invalid input syntax for type uuid')) {
    return '예약 ID 형식 오류입니다.\n'
        'Supabase SQL Editor에서 fix_rental_rpcs_bigint.sql 을 실행해주세요.';
  }
  if (msg.contains('reservations_status_check') ||
      msg.contains('check constraint')) {
    return 'in_use 상태가 DB에 없습니다.\n'
        'Supabase SQL Editor에서 setup_rental_start.sql 을 실행해주세요.';
  }
  if (msg.contains('does not exist') || msg.contains('42703')) {
    return '대여 시작 컬럼이 DB에 없습니다.\n'
        'Supabase SQL Editor에서 setup_rental_start.sql 을 실행해주세요.';
  }
  if (msg.contains('could not find the function') &&
      msg.contains('start_rental_for_me')) {
    return '대여 시작 RPC가 설치되지 않았습니다.\n'
        'Supabase SQL Editor에서 setup_rental_start.sql 을 실행해주세요.';
  }
  if (msg.contains('row-level security') || msg.contains('policy')) {
    return '대여 시작 저장 권한이 없습니다. RLS 정책을 확인해주세요.';
  }

  return error.message;
}
