import 'package:flutter/foundation.dart';

import '../models/staff_profile.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

class StaffRepository {
  Future<StaffProfile?> fetchMyProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[StaffRepository] fetchMyProfile: no auth user');
      return null;
    }

    final row = await withNetworkRetry(
      () => supabase
          .from('staff_users')
          .select(
            'user_id, complex_id, display_name, role, approved, phone, company_name, complexes(name)',
          )
          .eq('user_id', user.id)
          .maybeSingle(),
    );

    if (row == null) {
      debugPrint(
        '[StaffRepository] staff_users: no row for user_id=${user.id}',
      );
      return null;
    }

    final map = Map<String, dynamic>.from(row);
    final rowUserId = map['user_id']?.toString();
    if (rowUserId != user.id) {
      debugPrint(
        '[StaffRepository] staff_users user_id mismatch: '
        'auth=${user.id} row=$rowUserId',
      );
      return null;
    }

    final profile = StaffProfile.fromMap(map);
    debugPrint(
      '[StaffRepository] staff_users OK: user_id=${profile.userId} '
      'approved=${profile.approved} complex=${profile.complexId}',
    );
    return profile;
  }

  Stream<StaffProfile?> watchMyProfile() async* {
    final user = supabase.auth.currentUser;
    if (user == null) {
      yield null;
      return;
    }

    var profile = await fetchMyProfile();
    yield profile;

    // 관리자 계정만 승인 상태 폴링 (입주민은 staff 조회 1회 후 종료)
    if (profile == null) return;

    await for (final _ in Stream.periodic(const Duration(seconds: 3))) {
      if (supabase.auth.currentUser?.id != user.id) break;
      try {
        profile = await fetchMyProfile();
        yield profile;
      } catch (_) {}
      if (profile == null) break;
    }
  }
}
