import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

/// 입주민 단지 차량 목록 — DB RLS(`vehicles_resident_select_own_complex`)가
/// complex_id 격리를 강제하므로 클라이언트 `.eq('complex_id')` 필터는 사용하지 않음.
class VehicleService {
  Future<VehicleQueryResult> fetchVehiclesForMyComplex() async {
    return withNetworkRetry(_fetchVehiclesForMyComplex);
  }

  Future<VehicleQueryResult> _fetchVehiclesForMyComplex() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const VehicleQueryResult(
        vehicles: [],
        issue: VehicleLoadIssue.notLoggedIn,
      );
    }

    final row = await supabase
        .from('residents')
        .select('complex_id, approved, complexes(name, invite_code)')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) {
      return const VehicleQueryResult(
        vehicles: [],
        issue: VehicleLoadIssue.notResident,
      );
    }

    final approved = row['approved'] == true;
    final complexId = row['complex_id']?.toString();
    final complexRaw = row['complexes'];
    final complexMap =
        complexRaw is Map ? Map<String, dynamic>.from(complexRaw) : null;
    final complexName = complexMap?['name']?.toString();
    final inviteCode = complexMap?['invite_code']?.toString();

    // RLS도 미승인 입주민 SELECT 를 차단하지만, 불필요한 API 호출·UX 혼선 방지
    if (!approved) {
      return VehicleQueryResult(
        vehicles: [],
        complexId: complexId,
        complexName: complexName,
        inviteCode: inviteCode,
        issue: VehicleLoadIssue.notApproved,
      );
    }

    if (complexId == null || complexId.isEmpty) {
      return VehicleQueryResult(
        vehicles: [],
        complexName: complexName,
        inviteCode: inviteCode,
        issue: VehicleLoadIssue.notResident,
      );
    }

    final rows = await _selectVehiclesVisibleByRls();
    final vehicles = rows.map(Vehicle.fromMap).toList();

    return VehicleQueryResult(
      vehicles: vehicles,
      complexId: complexId,
      complexName: complexName,
      inviteCode: inviteCode,
      issue: vehicles.isEmpty
          ? VehicleLoadIssue.emptyForComplex
          : VehicleLoadIssue.none,
    );
  }

  /// RLS가 허용한 차량만 반환 (본인 단지 + 승인 입주민).
  Future<List<Map<String, dynamic>>> _selectVehiclesVisibleByRls() async {
    final query = supabase.from('vehicles').select();

    try {
      return await query.order('created_at');
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        return query.order('id');
      }
      rethrow;
    }
  }
}
