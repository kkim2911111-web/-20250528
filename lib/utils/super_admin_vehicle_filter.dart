import '../models/super_admin_models.dart';
import '../screens/super_admin/super_admin_nav.dart';

/// 최고관리자 차량 목록 필터 (가용·대여중·전체)
List<SuperAdminVehicle> applySuperAdminVehicleFilter({
  required List<SuperAdminVehicle> list,
  required SuperAdminVehicleFilter filter,
  String? complexId,
}) {
  var result = list;
  if (complexId != null) {
    result = result.where((v) => v.complexId == complexId).toList();
  }
  switch (filter) {
    case SuperAdminVehicleFilter.available:
      return result.where((v) => !v.inUse && v.isAvailable).toList();
    case SuperAdminVehicleFilter.inUse:
      return result.where((v) => v.inUse).toList();
    case SuperAdminVehicleFilter.all:
      return result;
  }
}
