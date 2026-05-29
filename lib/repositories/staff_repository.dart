import '../models/staff_profile.dart';
import '../supabase_client.dart';

class StaffRepository {
  Future<StaffProfile?> fetchMyProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final row = await supabase
        .from('staff_users')
        .select('user_id, complex_id, display_name, role, approved, complexes(name)')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return StaffProfile.fromMap(Map<String, dynamic>.from(row));
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
      profile = await fetchMyProfile();
      yield profile;
      if (profile == null) break;
    }
  }
}
