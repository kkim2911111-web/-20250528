import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

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

    final rows = await _selectVehicles(complexId);
    final vehicles = rows.map(Vehicle.fromMap).toList();

    return VehicleQueryResult(
      vehicles: vehicles,
      complexId: complexId,
      complexName: complexName,
      inviteCode: inviteCode,
      issue: vehicles.isEmpty ? VehicleLoadIssue.emptyForComplex : VehicleLoadIssue.none,
    );
  }

  Future<List<Map<String, dynamic>>> _selectVehicles(String complexId) async {
    var query = supabase.from('vehicles').select().eq('complex_id', complexId);

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
