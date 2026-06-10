import 'package:flutter/material.dart';

import '../models/app_maintenance_status.dart';
import '../services/app_maintenance_service.dart';
import '../theme/danji_colors.dart';
import 'maintenance_mode_screen.dart';

/// 예약·결제 화면 — 점검모드 시 전체 안내 (내 예약·반납 링크 제공)
class MaintenanceModeGate extends StatefulWidget {
  final Widget child;
  final VoidCallback? onMyReservations;
  final VoidCallback? onReturn;

  const MaintenanceModeGate({
    super.key,
    required this.child,
    this.onMyReservations,
    this.onReturn,
  });

  @override
  State<MaintenanceModeGate> createState() => _MaintenanceModeGateState();
}

class _MaintenanceModeGateState extends State<MaintenanceModeGate> {
  late Future<AppMaintenanceStatus> _future;

  @override
  void initState() {
    super.initState();
    _future = AppMaintenanceService.instance.current(force: true);
  }

  Future<void> _reload() async {
    final next = AppMaintenanceService.instance.fetch(force: true);
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppMaintenanceStatus>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            backgroundColor: DanjiColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final status = snap.data ?? AppMaintenanceStatus.disabled;
        if (!status.enabled) return widget.child;

        return MaintenanceModeScreen(
          message: status.message,
          onMyReservations: widget.onMyReservations,
          onReturn: widget.onReturn,
          onRefresh: _reload,
        );
      },
    );
  }
}
