import 'package:flutter/foundation.dart';
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
        signupCompleted: false,
        role: 'resident',
        residentApproved: resident.approved,
        hasResidentRegistration: resident.registered,
        residentVerificationRequested: false,
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
      licenseVerified: row['license_verified'] == true,
      licenseRejectionReason: row['license_rejection_reason']?.toString(),
      hasPaymentCard: row['payment_card_registered'] == true ||
          (row['toss_billing_key']?.toString().isNotEmpty ?? false),
      cardLast4: row['payment_card_last4']?.toString(),
      points: (row['points'] as num?)?.toInt() ?? 0,
      couponCount: (row['coupon_count'] as num?)?.toInt() ?? 0,
      signupCompleted: row['signup_completed'] == true,
      role: row['role']?.toString() ?? 'resident',
      residentApproved: resident.approved,
      hasResidentRegistration: resident.registered,
      residentVerificationRequested:
          row['resident_verification_requested'] == true,
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
          .select('complex_id, building, unit, approved, complexes(name)')
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

      final complexId = row['complex_id']?.toString();
      var complexName = _parseComplexNameFromRow(row);

      complexName ??= await _fetchComplexNameById(complexId);
      complexName ??= await _fetchMyResidentComplexNameRpc();

      if (kDebugMode && (complexName == null || complexName.isEmpty)) {
        debugPrint(
          '[MyPageService] resident complex name missing '
          'user_id=$userId complex_id=$complexId',
        );
      }

      return (
        registered: true,
        approved: row['approved'] == true,
        complexName: complexName,
        building: row['building']?.toString(),
        unit: row['unit']?.toString(),
      );
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == '42703') {
        return (
          registered: false,
          approved: false,
          complexName: null,
          building: null,
          unit: null,
        );
      }
      rethrow;
    }
  }

  String? _parseComplexNameFromRow(Map<String, dynamic> row) {
    final complexRaw = row['complexes'];
    if (complexRaw is Map) {
      final name = Map<String, dynamic>.from(complexRaw)['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  /// residents.complex_id → complexes.name (RLS: complexes_select_own_resident)
  Future<String?> _fetchComplexNameById(String? complexId) async {
    if (complexId == null || complexId.isEmpty) return null;

    try {
      final row = await supabase
          .from('complexes')
          .select('name')
          .eq('id', complexId)
          .maybeSingle();

      final name = row?['name']?.toString().trim();
      if (name == null || name.isEmpty) return null;
      return name;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint('[MyPageService] complexes select failed: ${e.message}');
      }
      return null;
    }
  }

  /// lookup RLS 차단 시 security definer RPC 폴백
  Future<String?> _fetchMyResidentComplexNameRpc() async {
    try {
      final raw = await supabase.rpc('get_my_resident_complex_name');
      final name = raw?.toString().trim();
      if (name == null || name.isEmpty) return null;
      return name;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          e.message.contains('get_my_resident_complex_name')) {
        return null;
      }
      if (kDebugMode) {
        debugPrint('[MyPageService] get_my_resident_complex_name: ${e.message}');
      }
      return null;
    }
  }

  /// 주민인증 화면 — 단지명 포함 입주민 정보 (마이페이지 프로필과 동일 소스)
  Future<({
    String? complexName,
    String? building,
    String? unit,
    bool approved,
    bool registered,
  })> fetchResidentVerificationInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }
    final resident = await _fetchResident(user.id);
    return (
      complexName: resident.complexName,
      building: resident.building,
      unit: resident.unit,
      approved: resident.approved,
      registered: resident.registered,
    );
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
    // 레거시 — submit_license_for_me RPC 사용 권장 (LicenseService)
    await supabase.rpc('submit_license_for_me', params: {
      'p_license_number': licenseNumber.trim(),
      'p_license_expiry': licenseExpiry.trim(),
      'p_license_photo_url': null,
    });
  }

  Future<void> savePaymentCard({required String cardLast4}) async {
    await _upsert({
      'payment_card_registered': true,
      'payment_card_last4': cardLast4.trim(),
    });
  }

  Future<String?> getUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final row = await supabase
          .from('user_profiles')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['role']?.toString();
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == '42703') return null;
      rethrow;
    }
  }

  Future<bool> isAdminUser() async => (await getUserRole()) == 'admin';

  Future<void> markAdminProfile({required String displayName}) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const AuthException('로그인이 필요합니다.');

    await _upsert({
      'role': 'admin',
      'full_name': displayName.trim(),
      'email': user.email,
      'signup_completed': true,
    });
  }

  Future<bool> isResidentVerificationRequested() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final row = await supabase
          .from('user_profiles')
          .select('resident_verification_requested')
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['resident_verification_requested'] == true;
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == '42703') return false;
      rethrow;
    }
  }

  Future<void> markResidentVerificationRequested() async {
    await _upsert({'resident_verification_requested': true});
  }

  Future<bool> hasUserProfileRow() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final row = await supabase
          .from('user_profiles')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return false;
      rethrow;
    }
  }

  /// 온보딩 미완료 + step 0 (새로고침 시 이메일 회원가입 화면으로)
  Future<bool> shouldShowEmailSignUpEntry() async {
    if (await isSignupCompleted()) return false;
    final step = await getOnboardingStep() ?? 0;
    if (step != 0) return false;
    return hasUserProfileRow();
  }

  Future<bool> isSignupCompleted() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final row = await supabase
          .from('user_profiles')
          .select('signup_completed')
          .eq('user_id', user.id)
          .maybeSingle();
      return row?['signup_completed'] == true;
    } on PostgrestException catch (e) {
      if (e.code == '42P01') return false;
      rethrow;
    }
  }

  Future<void> markSignupComplete() async {
    await _upsert({
      'signup_completed': true,
      'onboarding_step': 4,
    });
  }

  Future<int?> getOnboardingStep() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final row = await supabase
          .from('user_profiles')
          .select('onboarding_step')
          .eq('user_id', user.id)
          .maybeSingle();
      return (row?['onboarding_step'] as num?)?.toInt();
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == '42703') return null;
      rethrow;
    }
  }

  Future<void> saveOnboardingStep(int step) async {
    final clamped = step.clamp(0, 4);
    await _upsert({'onboarding_step': clamped});
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
