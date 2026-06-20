import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reservation.dart';
import '../supabase_client.dart';
import 'push_notification_service.dart';
import 'rental_service.dart';

/// 대여하기 3단계 — 사진 · 면허 · 문열림 전용
class RentalStartService {
  static const bucketName = 'rental-photos';
  static const minPhotos = 6;
  static const maxPhotos = 10;
  static const guidedPhotoLabels = [
    '전면',
    '후면',
    '좌측면',
    '우측면',
    '실내',
  ];
  static const pickupSlotLabels = [
    '전면',
    '후면',
    '좌측면',
    '우측면',
    '실내',
    '계기판',
  ];

  static const _select = '''
id,user_id,vehicle_id,start_at,end_at,start_time,end_time,total_price,status,
pickup_photos,photos_uploaded,license_verified,rental_started_at
''';

  /// 대여하기 진입 시 — confirmed/pending 예약의 이전 준비 상태 초기화
  Future<Reservation> prepareRentalStartSession(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final current = await fetchReservation(reservationId);
    if (current.status == 'in_use') {
      debugPrint(
        '[rental-start] prepare skip (already in_use) reservationId=$reservationId',
      );
      return current;
    }
    if (current.status != 'confirmed' && current.status != 'pending') {
      return current;
    }

    if (!current.photosUploaded &&
        !current.licenseVerified &&
        current.pickupPhotos.isEmpty) {
      return current;
    }

    final idFilter = _idFilter(reservationId);
    debugPrint(
      '[rental-start] prepare reset reservationId=$reservationId '
      'was photos_uploaded=${current.photosUploaded} '
      'license_verified=${current.licenseVerified} '
      'pickup_photos=${current.pickupPhotos.length}',
    );

    try {
      final row = await supabase
          .from('reservations')
          .update({
            'photos_uploaded': false,
            'license_verified': false,
            'pickup_photos': <String>[],
          })
          .eq('id', idFilter)
          .eq('user_id', user.id)
          .inFilter('status', ['confirmed', 'pending'])
          .select('id, photos_uploaded, license_verified, pickup_photos, status')
          .maybeSingle();

      if (row == null) {
        debugPrint(
          '[rental-start] prepare reset: 0 rows (status changed or RLS)',
        );
        return fetchReservation(reservationId);
      }

      debugPrint(
        '[rental-start] prepare reset OK reservationId=$reservationId row=$row',
      );
      RentalService.signalListRefresh();
      return fetchReservation(reservationId);
    } on PostgrestException catch (e) {
      _logPostgrestError('prepareRentalStartSession', e,
          reservationId: reservationId);
      rethrow;
    }
  }

  Future<Reservation> fetchReservation(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    Map<String, dynamic>? row;
    for (final select in ['$_select, vehicles(*)', _select]) {
      try {
        row = await supabase
            .from('reservations')
            .select(select)
            .eq('id', _idFilter(reservationId))
            .eq('user_id', user.id)
            .maybeSingle();
        if (row != null) break;
      } on PostgrestException catch (e) {
        if (!_missingColumn(e)) rethrow;
      }
    }

    if (row == null) {
      throw const RentalException('예약 정보를 찾을 수 없습니다.');
    }

    final reservation = Reservation.fromMap(Map<String, dynamic>.from(row));
    if (reservation.vehicle == null) {
      return RentalService().fetchReservation(reservationId);
    }
    return reservation;
  }

  /// STEP 1 — Storage 업로드 + photos_uploaded=true
  Future<List<String>> uploadPickupPhotos({
    required String reservationId,
    required List<Uint8List> photos,
    void Function(int completed, int total)? onProgress,
  }) async {
    debugPrint(
      '[rental-start] 사진 업로드 시작 reservationId=$reservationId '
      'count=${photos.length}',
    );

    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[rental-start] 사진 업로드 실패: 로그인 필요');
      throw const AuthException('로그인이 필요합니다.');
    }
    if (photos.length < minPhotos) {
      debugPrint('[rental-start] 사진 업로드 실패: 최소 $minPhotos장 미만');
      throw RentalException('사진을 최소 $minPhotos장 등록해주세요.');
    }
    if (photos.length > maxPhotos) {
      debugPrint('[rental-start] 사진 업로드 실패: 최대 $maxPhotos장 초과');
      throw RentalException('사진은 최대 $maxPhotos장까지 등록할 수 있습니다.');
    }

    try {
      final urls = <String>[];
      for (var i = 0; i < photos.length; i++) {
        final path =
            '${user.id}/$reservationId/pickup/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await supabase.storage.from(bucketName).uploadBinary(
              path,
              photos[i],
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        urls.add(supabase.storage.from(bucketName).getPublicUrl(path));
        onProgress?.call(i + 1, photos.length);
      }
      debugPrint(
        '[rental-start] Storage 업로드 완료 reservationId=$reservationId '
        'urls=${urls.length}',
      );

      await _updatePickupPhotoUrls(
        reservationId: reservationId,
        userId: user.id,
        urls: urls,
      );

      final photosUploadedOk = await _setPhotosUploadedTrue(
        reservationId: reservationId,
        userId: user.id,
      );

      if (!photosUploadedOk) {
        await _diagnosePhotosUploadedUpdate(
          reservationId: reservationId,
          userId: user.id,
          reason: 'photos_uploaded update returned false or 0 rows',
        );
        throw const RentalException(
          '사진 업로드는 완료됐지만 photos_uploaded 저장에 실패했습니다.\n'
          '콘솔 [rental-start] RLS 진단 로그를 확인해주세요.',
        );
      }

      final rawRow = await supabase
          .from('reservations')
          .select('id, photos_uploaded, pickup_photos, user_id, status')
          .eq('id', _idFilter(reservationId))
          .eq('user_id', user.id)
          .maybeSingle();
      final rawPhotosUploaded = rawRow?['photos_uploaded'];
      final rawPickupCount =
          (rawRow?['pickup_photos'] as List?)?.length ?? 0;
      debugPrint(
        '[rental-start] DB 최종 확인 reservationId=$reservationId '
        'photos_uploaded=$rawPhotosUploaded '
        '(type=${rawPhotosUploaded.runtimeType}) '
        'pickup_photos_count=$rawPickupCount '
        'status=${rawRow?['status']}',
      );

      final verified = await fetchReservation(reservationId);
      if (!verified.isRentalPhotosReady) {
        await _diagnosePhotosUploadedUpdate(
          reservationId: reservationId,
          userId: user.id,
          reason: 'isRentalPhotosReady still false after update',
        );
        throw const RentalException(
          '사진 업로드는 완료됐지만 photos_uploaded 저장에 실패했습니다.\n'
          '콘솔 [rental-start] RLS 진단 로그를 확인해주세요.',
        );
      }

      debugPrint(
        '[rental-start] 사진 업로드 성공 reservationId=$reservationId '
        'photos_uploaded=true pickup_photos=${verified.pickupPhotos.length}',
      );
      RentalService.signalListRefresh();
      return urls;
    } catch (e, st) {
      if (e is! RentalException && e is! AuthException) {
        debugPrint(
          '[rental-start] 사진 업로드 실패 reservationId=$reservationId '
          'error=$e',
        );
        debugPrint('[rental-start] stack: $st');
      } else if (e is RentalException) {
        debugPrint(
          '[rental-start] 사진 업로드 실패 reservationId=$reservationId '
          'reason=${e.message}',
        );
      }
      rethrow;
    }
  }

  /// STEP 2 — confirm_rental_license_for_me (photos_uploaded 확인 후)
  Future<void> confirmLicense(String reservationId) async {
    final reservation = await fetchReservation(reservationId);
    if (!reservation.isRentalPhotosReady) {
      throw const RentalException(
        '사진 등록이 완료되지 않았습니다. 갤러리에서 6장 이상 선택 후 업로드가 끝난 뒤 다시 시도해주세요.',
      );
    }

    await supabase.rpc('confirm_rental_license_for_me', params: {
      'p_reservation_id': reservationId,
    });
    final verified = await fetchReservation(reservationId);
    if (!verified.licenseVerified) {
      throw const RentalException(
        '면허 확인이 DB에 반영되지 않았습니다. (license_verified=false)',
      );
    }
    RentalService.signalListRefresh();
  }

  /// STEP 3 — start_rental_for_me
  Future<Reservation> startRental({
    required String reservationId,
    required List<String> pickupPhotoUrls,
  }) async {
    if (pickupPhotoUrls.length < minPhotos) {
      throw const RentalException('대여 시작에 필요한 사진이 없습니다.');
    }

    await supabase.rpc('start_rental_for_me', params: {
      'p_reservation_id': reservationId,
      'p_pickup_photos': pickupPhotoUrls,
      'p_mileage_start': null,
      'p_fuel_level_start': null,
    });

    final updated = await fetchReservation(reservationId);
    if (updated.status != 'in_use') {
      throw const RentalException(
        '대여 시작이 DB에 반영되지 않았습니다.\n'
        'Supabase에서 fix_start_rental_for_me.sql 을 실행해주세요.',
      );
    }

    RentalService.signalListRefresh();
    try {
      await RentalService.notifyStaffRentalStarted(updated);
    } catch (e) {
      debugPrint('[rental-start] staff rental push skipped (non-fatal): $e');
    }
    return updated;
  }

  Object _idFilter(String reservationId) {
    if (RegExp(r'^\d+$').hasMatch(reservationId.trim())) {
      return int.parse(reservationId.trim());
    }
    return reservationId;
  }

  Future<void> _updatePickupPhotoUrls({
    required String reservationId,
    required String userId,
    required List<String> urls,
  }) async {
    final idFilter = _idFilter(reservationId);
    try {
      final row = await supabase
          .from('reservations')
          .update({'pickup_photos': urls})
          .eq('id', idFilter)
          .eq('user_id', userId)
          .select('id, pickup_photos')
          .maybeSingle();

      if (row == null) {
        debugPrint(
          '[rental-start] pickup_photos update: 0 rows affected '
          'reservationId=$reservationId idFilter=$idFilter (${idFilter.runtimeType})',
        );
        throw const RentalException(
          'pickup_photos 저장에 실패했습니다. 예약 ID 또는 RLS 정책을 확인해주세요.',
        );
      }

      final count = (row['pickup_photos'] as List?)?.length ?? 0;
      debugPrint(
        '[rental-start] pickup_photos 저장 완료 reservationId=$reservationId '
        'count=$count',
      );
    } on PostgrestException catch (e) {
      _logPostgrestError('pickup_photos update', e, reservationId: reservationId);
      if (_missingColumn(e)) {
        throw const RentalException(
          'pickup_photos 컬럼이 DB에 없습니다.\n'
          'Supabase SQL Editor에서 setup_rental_start.sql 을 실행해주세요.',
        );
      }
      rethrow;
    }
  }

  /// photos_uploaded=true — Supabase client 직접 update (RPC 미사용)
  Future<bool> _setPhotosUploadedTrue({
    required String reservationId,
    required String userId,
  }) async {
    final idFilter = _idFilter(reservationId);
    debugPrint(
      '[rental-start] photos_uploaded update 시작 '
      'reservationId=$reservationId idFilter=$idFilter (${idFilter.runtimeType})',
    );

    await _diagnosePhotosUploadedUpdate(
      reservationId: reservationId,
      userId: userId,
      reason: 'before photos_uploaded update',
    );

    try {
      // 1) 요청하신 방식: id만으로 직접 update + select로 반영 행 확인
      var row = await supabase
          .from('reservations')
          .update({'photos_uploaded': true})
          .eq('id', idFilter)
          .select('id, user_id, photos_uploaded, status')
          .maybeSingle();

      if (row == null) {
        debugPrint(
          '[rental-start] photos_uploaded update (id only): 0 rows — '
          'user_id 필터로 재시도',
        );
        row = await supabase
            .from('reservations')
            .update({'photos_uploaded': true})
            .eq('id', idFilter)
            .eq('user_id', userId)
            .select('id, user_id, photos_uploaded, status')
            .maybeSingle();
      }

      if (row == null) {
        debugPrint(
          '[rental-start] photos_uploaded update 실패: 0 rows affected '
          '(RLS 거부 또는 id/user_id 불일치 가능)',
        );
        return false;
      }

      final saved = row['photos_uploaded'] == true;
      debugPrint(
        '[rental-start] photos_uploaded update 결과 '
        'saved=$saved row=$row',
      );
      return saved;
    } on PostgrestException catch (e) {
      _logPostgrestError('photos_uploaded update', e, reservationId: reservationId);
      if (_missingColumn(e)) {
        throw const RentalException(
          'photos_uploaded 컬럼이 DB에 없습니다.\n'
          'Supabase SQL Editor에서 fix_start_rental_for_me.sql 을 실행해주세요.',
        );
      }
      rethrow;
    }
  }

  /// RLS / 권한 진단 — photos_uploaded update 가능 여부
  Future<void> _diagnosePhotosUploadedUpdate({
    required String reservationId,
    required String userId,
    required String reason,
  }) async {
    final idFilter = _idFilter(reservationId);
    debugPrint('[rental-start] === RLS 진단 ($reason) ===');
    debugPrint(
      '[rental-start] auth.uid=$userId '
      'reservationId=$reservationId idFilter=$idFilter (${idFilter.runtimeType})',
    );

    // SELECT 권한 (본인 row 조회)
    try {
      final byIdUser = await supabase
          .from('reservations')
          .select('id, user_id, status, photos_uploaded, pickup_photos')
          .eq('id', idFilter)
          .eq('user_id', userId)
          .maybeSingle();
      if (byIdUser == null) {
        debugPrint(
          '[rental-start] RLS 진단: id+user_id SELECT → 행 없음 '
          '(예약 미존재 또는 SELECT RLS 차단)',
        );
      } else {
        final pickupLen = (byIdUser['pickup_photos'] as List?)?.length ?? 0;
        debugPrint(
          '[rental-start] RLS 진단: id+user_id SELECT OK '
          'status=${byIdUser['status']} '
          'photos_uploaded=${byIdUser['photos_uploaded']} '
          'pickup_photos=$pickupLen '
          'row_user_id=${byIdUser['user_id']}',
        );
        if (byIdUser['user_id']?.toString() != userId) {
          debugPrint(
            '[rental-start] RLS 진단: user_id 불일치 '
            'row=${byIdUser['user_id']} auth=$userId',
          );
        }
      }
    } on PostgrestException catch (e) {
      _logPostgrestError('RLS diagnose SELECT id+user_id', e,
          reservationId: reservationId);
    }

    // id만으로 SELECT (다른 유저 row 노출 여부 — 보통 RLS로 null)
    try {
      final byIdOnly = await supabase
          .from('reservations')
          .select('id, user_id, photos_uploaded')
          .eq('id', idFilter)
          .maybeSingle();
      debugPrint(
        '[rental-start] RLS 진단: id only SELECT → '
        '${byIdOnly == null ? "행 없음 (RLS 또는 미존재)" : byIdOnly}',
      );
    } on PostgrestException catch (e) {
      _logPostgrestError('RLS diagnose SELECT id only', e,
          reservationId: reservationId);
    }

    // UPDATE 권한 probe — select 반환으로 실제 반영 행 수 확인
    try {
      final probe = await supabase
          .from('reservations')
          .update({'photos_uploaded': true})
          .eq('id', idFilter)
          .eq('user_id', userId)
          .select('id, photos_uploaded')
          .maybeSingle();
      debugPrint(
        '[rental-start] RLS 진단: UPDATE probe (id+user_id) → '
        '${probe == null ? "0 rows (UPDATE RLS 차단 또는 조건 불일치)" : probe}',
      );
    } on PostgrestException catch (e) {
      _logPostgrestError('RLS diagnose UPDATE probe', e,
          reservationId: reservationId);
      debugPrint(
        '[rental-start] RLS 진단: UPDATE 거부됨 — '
        'reservations UPDATE 정책(reservations_update_own) 확인 필요',
      );
    }

    debugPrint(
      '[rental-start] RLS 진단 힌트: Supabase SQL Editor에서 '
      'reservations UPDATE policy (user_id = auth.uid()) 존재 여부 확인',
    );
    debugPrint('[rental-start] === RLS 진단 끝 ===');
  }

  void _logPostgrestError(
    String action,
    PostgrestException e, {
    required String reservationId,
  }) {
    debugPrint(
      '[rental-start] $action 실패 reservationId=$reservationId\n'
      '  code=${e.code}\n'
      '  message=${e.message}\n'
      '  details=${e.details}\n'
      '  hint=${e.hint}',
    );
  }

  bool _missingColumn(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('does not exist') ||
        msg.contains('42703') ||
        msg.contains('schema cache') ||
        msg.contains('photos_uploaded');
  }
}
