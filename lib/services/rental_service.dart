import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fuel_level.dart';
import '../models/reservation.dart';
import '../supabase_client.dart';

class RentalException implements Exception {
  final String message;
  const RentalException(this.message);

  @override
  String toString() => message;
}

class RentalService {
  static const bucketName = 'rental-photos';

  Future<List<Reservation>> fetchMyReservations() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final rows = await supabase
        .from('reservations')
        .select('*, vehicles(*)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => Reservation.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Reservation> fetchReservation(String reservationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final row = await supabase
        .from('reservations')
        .select('*, vehicles(*)')
        .eq('id', reservationId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) {
      throw const RentalException('예약 정보를 찾을 수 없습니다.');
    }

    return Reservation.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<String>> uploadPhotos({
    required String reservationId,
    required String phase,
    required List<Uint8List> photos,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    if (photos.isEmpty) {
      throw const RentalException('사진을 1장 이상 등록해주세요.');
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

  Future<Map<String, dynamic>> startRental({
    required String reservationId,
    required List<Uint8List> photos,
    required int mileageStart,
    required FuelLevel fuelLevelStart,
  }) async {
    final photoUrls = await uploadPhotos(
      reservationId: reservationId,
      phase: 'pickup',
      photos: photos,
    );

    try {
      final data = await supabase.rpc('start_rental_for_me', params: {
        'p_reservation_id': reservationId,
        'p_pickup_photos': photoUrls,
        'p_mileage_start': mileageStart,
        'p_fuel_level_start': fuelLevelStart.value,
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
    final photoUrls = await uploadPhotos(
      reservationId: reservationId,
      phase: 'return',
      photos: photos,
    );

    try {
      final data = await supabase.rpc('complete_rental_for_me', params: {
        'p_reservation_id': reservationId,
        'p_return_photos': photoUrls,
        'p_mileage_end': mileageEnd,
        'p_fuel_level_end': fuelLevelEnd.value,
        'p_is_accident': isAccident,
        'p_accident_note': accidentNote,
      });
      return _asMap(data);
    } on PostgrestException catch (e) {
      throw RentalException(friendlyRentalError(e));
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
}

String friendlyRentalError(PostgrestException error) {
  final msg = error.message.toLowerCase();

  if (msg.contains('photos_required')) {
    return '차량 사진을 1장 이상 등록해주세요.';
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
    return '현재 상태에서는 진행할 수 없습니다.';
  }
  if (msg.contains('too_early')) {
    return '대여 시작 가능 시간이 아닙니다. (예약 시작 30분 전부터 가능)';
  }
  if (msg.contains('expired')) {
    return '예약 시간이 지나 대여를 시작할 수 없습니다.';
  }
  if (msg.contains('could not find the function')) {
    return '대여 RPC가 설치되지 않았습니다.\nSupabase에서 rental_rpcs.sql 을 실행해주세요.';
  }
  if (msg.contains('row-level security') || msg.contains('policy')) {
    return '저장 권한이 없습니다. Storage 버킷 정책을 확인해주세요.';
  }

  return error.message;
}
