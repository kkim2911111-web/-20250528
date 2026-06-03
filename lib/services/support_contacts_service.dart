import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import '../utils/network_retry.dart';

/// `app_support_contacts` — 배너와 같이 DB에서 실시간 조회
class SupportContactsService {
  static const emergencyPhoneKey = 'emergency_phone';
  static const rentalInquiryPhoneKey = 'rental_inquiry';

  /// 긴급 상담 대표번호 (유효하지 않으면 null)
  Future<String?> fetchEmergencyPhone() async {
    final fromKey = await fetchPhoneByKey(emergencyPhoneKey);
    if (fromKey != null) return fromKey;

    if (!isSupabaseInitialized) return null;
    if (supabase.auth.currentUser == null) return null;

    try {
      final raw = await supabase.rpc('get_emergency_phone');
      return normalizePhone(raw?.toString());
    } on PostgrestException catch (e) {
      debugPrint('[SupportContacts] get_emergency_phone failed: ${e.message}');
    }

    return null;
  }

  /// 일반렌트 문의 전화 (`app_support_contacts.rental_inquiry`)
  Future<String?> fetchRentalInquiryPhone() =>
      fetchPhoneByKey(rentalInquiryPhoneKey);

  Future<String?> fetchPhoneByKey(String key) async {
    if (!isSupabaseInitialized) return null;
    if (supabase.auth.currentUser == null) return null;

    try {
      final row = await withNetworkRetry(
        () => supabase
            .from('app_support_contacts')
            .select('value')
            .eq('key', key)
            .maybeSingle(),
      );
      return normalizePhone(row?['value']?.toString());
    } on PostgrestException catch (e) {
      debugPrint('[SupportContacts] $key select failed: ${e.message}');
      return null;
    }
  }

  static String? normalizePhone(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final upper = value.toUpperCase();
    if (upper == 'EMPTY' || upper == 'NULL' || upper == '-') return null;
    return value;
  }
}
