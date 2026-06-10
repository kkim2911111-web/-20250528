import 'package:flutter/material.dart';

import '../models/super_admin_models.dart';
import '../screens/super_admin/super_admin_common.dart';
import '../theme/danji_colors.dart';

/// 정산 대시보드 카드 기준월 — 항상 전월(당월은 마감 전이라 제외).
({int year, int month}) superAdminSettlementDashboardPeriod([DateTime? now]) {
  final anchor = now ?? DateTime.now();
  final prev = DateTime(anchor.year, anchor.month - 1, 1);
  return (year: prev.year, month: prev.month);
}

enum SuperAdminSettlementDashboardKind { requested, unsettled, complete }

class SuperAdminSettlementDashboardCard {
  final int year;
  final int month;
  final SuperAdminSettlementDashboardKind kind;
  final int count;

  const SuperAdminSettlementDashboardCard({
    required this.year,
    required this.month,
    required this.kind,
    this.count = 0,
  });

  String get label {
    switch (kind) {
      case SuperAdminSettlementDashboardKind.requested:
        return '정산요청';
      case SuperAdminSettlementDashboardKind.unsettled:
        return '미정산';
      case SuperAdminSettlementDashboardKind.complete:
        return '정산';
    }
  }

  String get value {
    switch (kind) {
      case SuperAdminSettlementDashboardKind.requested:
      case SuperAdminSettlementDashboardKind.unsettled:
        return '$count건';
      case SuperAdminSettlementDashboardKind.complete:
        return '완료';
    }
  }

  Color get color {
    switch (kind) {
      case SuperAdminSettlementDashboardKind.requested:
        return DanjiColors.danger;
      case SuperAdminSettlementDashboardKind.unsettled:
        return SuperAdminUiColors.inUseOrange;
      case SuperAdminSettlementDashboardKind.complete:
        return SuperAdminUiColors.availableGreen;
    }
  }

  static SuperAdminSettlementDashboardCard fromRevenueRows(
    List<SuperAdminRevenueRow> rows, {
    required int year,
    required int month,
  }) {
    final requested = rows
        .where((r) => r.isRequested && !r.isSettled)
        .length;
    if (requested > 0) {
      return SuperAdminSettlementDashboardCard(
        year: year,
        month: month,
        kind: SuperAdminSettlementDashboardKind.requested,
        count: requested,
      );
    }

    final unsettled = rows
        .where((r) => !r.isSettled && !r.isRequested && r.totalRevenue > 0)
        .length;
    if (unsettled > 0) {
      return SuperAdminSettlementDashboardCard(
        year: year,
        month: month,
        kind: SuperAdminSettlementDashboardKind.unsettled,
        count: unsettled,
      );
    }

    return SuperAdminSettlementDashboardCard(
      year: year,
      month: month,
      kind: SuperAdminSettlementDashboardKind.complete,
    );
  }
}
