import 'package:flutter/material.dart';

import '../models/super_admin_models.dart';
import '../screens/super_admin/super_admin_common.dart';
import '../theme/danji_colors.dart';

/// 플랫폼 수수료·청구 기본월 — 전월(당월은 마감 전이라 제외).
({int year, int month}) superAdminSettlementDashboardPeriod([DateTime? now]) {
  final anchor = now ?? DateTime.now();
  final prev = DateTime(anchor.year, anchor.month - 1, 1);
  return (year: prev.year, month: prev.month);
}

/// 정산 카드 스캔 범위 — 당월 포함 과거 N개월(월별 패널과 동일).
const superAdminSettlementScanPastMonths = 36;

List<({int year, int month})> superAdminSettlementScanMonths([
  DateTime? now,
  int pastMonths = superAdminSettlementScanPastMonths,
]) {
  final anchor = now ?? DateTime.now();
  return List.generate(pastMonths + 1, (index) {
    final month = DateTime(anchor.year, anchor.month - index, 1);
    return (year: month.year, month: month.month);
  });
}

typedef SuperAdminMonthlyRevenueSnapshot = ({
  int year,
  int month,
  List<SuperAdminRevenueRow> rows,
});

enum SuperAdminSettlementDashboardKind { requested, unsettled, complete, none }

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
      case SuperAdminSettlementDashboardKind.none:
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
      case SuperAdminSettlementDashboardKind.none:
        return '없음';
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
      case SuperAdminSettlementDashboardKind.none:
        return DanjiColors.textMuted;
    }
  }

  static SuperAdminSettlementDashboardCard fromMonthlySnapshots(
    List<SuperAdminMonthlyRevenueSnapshot> snapshots, {
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final fallbackYear = anchor.year;
    final fallbackMonth = anchor.month;

    final ordered = [...snapshots]
      ..sort((a, b) {
        final byYear = a.year.compareTo(b.year);
        return byYear != 0 ? byYear : a.month.compareTo(b.month);
      });

    var requested = 0;
    var unsettled = 0;
    var anyRevenue = false;
    int? navYear;
    int? navMonth;

    for (final snap in ordered) {
      var monthHasPending = false;
      for (final row in snap.rows) {
        if (row.totalRevenue <= 0) continue;
        anyRevenue = true;
        if (row.isSettled) continue;
        monthHasPending = true;
        if (row.isRequested) {
          requested++;
        } else {
          unsettled++;
        }
      }
      if (monthHasPending && navYear == null) {
        navYear = snap.year;
        navMonth = snap.month;
      }
    }

    final nav = (
      year: navYear ?? fallbackYear,
      month: navMonth ?? fallbackMonth,
    );

    if (requested > 0) {
      return SuperAdminSettlementDashboardCard(
        year: nav.year,
        month: nav.month,
        kind: SuperAdminSettlementDashboardKind.requested,
        count: requested,
      );
    }
    if (unsettled > 0) {
      return SuperAdminSettlementDashboardCard(
        year: nav.year,
        month: nav.month,
        kind: SuperAdminSettlementDashboardKind.unsettled,
        count: unsettled,
      );
    }
    if (anyRevenue) {
      return SuperAdminSettlementDashboardCard(
        year: fallbackYear,
        month: fallbackMonth,
        kind: SuperAdminSettlementDashboardKind.complete,
      );
    }
    return SuperAdminSettlementDashboardCard(
      year: fallbackYear,
      month: fallbackMonth,
      kind: SuperAdminSettlementDashboardKind.none,
    );
  }

  static SuperAdminSettlementDashboardCard fromRevenueRows(
    List<SuperAdminRevenueRow> rows, {
    required int year,
    required int month,
  }) {
    return fromMonthlySnapshots([
      (year: year, month: month, rows: rows),
    ]);
  }
}
