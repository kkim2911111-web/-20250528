import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/my_page_profile.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class MyPageService {
  Future<MyPageProfile> fetchProfile() async {
    return withNetworkRetry(_fetchProfile);
  }

  Future<MyPageProfile> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final providers = user.identities
            ?.map((i) => i.provider)
            .whereType<String>()
            .toSet()
            .toList() ??
        [];
    if (providers.isEmpty && user.email != null) {
      providers.add('email');
    }

    Map<String, dynamic>? row;
    try {
      row = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (e.code != '42P01') rethrow;
    }

    if (row == null) {
      final resident = await _fetchResident(user.id);
      return MyPageProfile(
        email: user.email,
        linkedProviders: providers,
        residentApproved: resident.approved,
        hasResidentRegistration: resident.registered,
        residentComplexName: resident.complexName,
        residentBuilding: resident.building,
        residentUnit: resident.unit,
      );
    }

    final resident = await _fetchResident(user.id);

    return MyPageProfile(
      name: row['full_name']?.toString() ?? row['name']?.toString(),
      phone: row['phone']?.toString(),
      email: row['email']?.toString() ?? user.email,
      address: row['address']?.toString(),
      linkedProviders: providers,
      licenseNumber: row['license_number']?.toString(),
      licenseExpiry: row['license_expiry']?.toString(),
      hasPaymentCard: row['payment_card_registered'] == true,
      cardLast4: row['payment_card_last4']?.toString(),
      points: (row['points'] as num?)?.toInt() ?? 0,
      couponCount: (row['coupon_count'] as num?)?.toInt() ?? 0,
      residentApproved: resident.approved,
      hasResidentRegistration: resident.registered,
      residentComplexName: resident.complexName,
      residentBuilding: resident.building,
      residentUnit: resident.unit,
    );
  }

  Future<({
    bool registered,
    bool approved,
    String? complexName,
    String? building,
    String? unit,
  })> _fetchResident(String userId) async {
    try {
      final row = await supabase
          .from('residents')
          .select('building, unit, approved, complexes(name)')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        return (
          registered: false,
          approved: false,
          complexName: null,
          building: null,
          unit: null,
        );
      }
      final complexRaw = row['complexes'];
      final complexName = complexRaw is Map
          ? complexRaw['name']?.toString()
          : null;
      return (
        registered: true,
        approved: row['approved'] == true,
        complexName: complexName,
        building: row['building']?.toString(),
        unit: row['unit']?.toString(),
      );
    } catch (_) {
      return (
        registered: false,
        approved: false,
        complexName: null,
        building: null,
        unit: null,
      );
    }
  }

  Future<void> saveBasicInfo({
    required String name,
    required String phone,
    required String address,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const AuthException('로그인이 필요합니다.');

    await _upsert({
      'full_name': name.trim(),
      'phone': phone.trim(),
      'email': user.email,
      'address': address.trim(),
    });
  }

  Future<void> saveLicense({
    required String licenseNumber,
    required String licenseExpiry,
  }) async {
    await _upsert({
      'license_number': licenseNumber.trim(),
      'license_expiry': licenseExpiry.trim(),
    });
  }

  Future<void> savePaymentCard({required String cardLast4}) async {
    await _upsert({
      'payment_card_registered': true,
      'payment_card_last4': cardLast4.trim(),
    });
  }

  Future<void> _upsert(Map<String, dynamic> fields) async {
    final user = supabase.auth.currentUser!;
    await supabase.from('user_profiles').upsert({
      'user_id': user.id,
      ...fields,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
