import 'vehicle.dart';

enum VehicleLoadIssue {
  none,
  notLoggedIn,
  notResident,
  notApproved,
  emptyForComplex,
}

class VehicleQueryResult {
  final List<Vehicle> vehicles;
  final String? complexId;
  final String? complexName;
  final String? inviteCode;
  final VehicleLoadIssue issue;

  const VehicleQueryResult({
    required this.vehicles,
    this.complexId,
    this.complexName,
    this.inviteCode,
    this.issue = VehicleLoadIssue.none,
  });

  bool get hasComplex => complexId != null && complexId!.isNotEmpty;

  String get emptyMessage {
    switch (issue) {
      case VehicleLoadIssue.notLoggedIn:
        return '로그인이 필요합니다.';
      case VehicleLoadIssue.notResident:
        return '입주민 인증(초대코드·동/호)을 먼저 완료해주세요.';
      case VehicleLoadIssue.notApproved:
        return '입주민 승인 대기 중입니다.\nSupabase에서 approved = true 로 승인해주세요.';
      case VehicleLoadIssue.emptyForComplex:
        final label = complexName ?? inviteCode ?? '내 단지';
        return '$label에 등록된 차량이 없습니다.\n'
            'Supabase에서 vehicles.complex_id가 입주민 단지와 같은지 확인해주세요.';
      case VehicleLoadIssue.none:
        return '등록된 차량이 없습니다.';
    }
  }
}
