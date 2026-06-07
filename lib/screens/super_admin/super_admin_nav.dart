/// 최고관리자 셸 내비게이션 상태
enum SuperAdminMenu {
  dashboard,
  complexes,
  vehicles,
  staff,
  residents,
  coupons,
  reservations,
  revenue,
  system,
}

enum SuperAdminVehicleFilter { all, available, inUse }

class SuperAdminNavState {
  final SuperAdminMenu menu;
  final SuperAdminVehicleFilter vehicleFilter;
  final bool staffPendingOnly;
  final bool residentPendingOnly;

  const SuperAdminNavState({
    this.menu = SuperAdminMenu.dashboard,
    this.vehicleFilter = SuperAdminVehicleFilter.all,
    this.staffPendingOnly = false,
    this.residentPendingOnly = false,
  });

  SuperAdminNavState copyWith({
    SuperAdminMenu? menu,
    SuperAdminVehicleFilter? vehicleFilter,
    bool? staffPendingOnly,
    bool? residentPendingOnly,
  }) {
    return SuperAdminNavState(
      menu: menu ?? this.menu,
      vehicleFilter: vehicleFilter ?? this.vehicleFilter,
      staffPendingOnly: staffPendingOnly ?? this.staffPendingOnly,
      residentPendingOnly: residentPendingOnly ?? this.residentPendingOnly,
    );
  }

  static String menuTitle(SuperAdminMenu menu) {
    switch (menu) {
      case SuperAdminMenu.dashboard:
        return '대시보드';
      case SuperAdminMenu.complexes:
        return '단지 관리';
      case SuperAdminMenu.vehicles:
        return '차량 관리';
      case SuperAdminMenu.staff:
        return '스태프 관리';
      case SuperAdminMenu.residents:
        return '입주민 관리';
      case SuperAdminMenu.coupons:
        return '쿠폰 관리';
      case SuperAdminMenu.reservations:
        return '전체 예약';
      case SuperAdminMenu.revenue:
        return '정산 관리';
      case SuperAdminMenu.system:
        return '시스템';
    }
  }
}
