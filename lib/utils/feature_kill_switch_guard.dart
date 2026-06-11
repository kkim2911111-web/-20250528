import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import '../models/app_feature_config.dart';
import '../services/app_feature_config_service.dart';
import '../services/app_maintenance_service.dart';
import '../theme/danji_colors.dart';
import 'feature_kill_switch.dart';
import 'rental_pricing.dart';

/// 기능별 차단·전체 점검모드 공통 다이얼로그 제목
const featureBlockDialogTitle = '서비스 점검';

/// 전체 점검모드 우선 → 기능별 차단 확인. 허용 시 true.
Future<bool> ensureFeatureEnabled(
  BuildContext context,
  String featureKey, {
  bool forceRefresh = true,
}) async {
  final maintenance = await AppMaintenanceService.instance.current(
    force: forceRefresh,
  );
  if (maintenance.enabled) {
    if (!context.mounted) return false;
    await _showBlockDialog(context, maintenance.message);
    return false;
  }

  await AppFeatureConfigService.instance.fetch(force: forceRefresh);
  if (!AppFeatureConfigService.instance.isEnabled(featureKey)) {
    if (!context.mounted) return false;
    await _showBlockDialog(
      context,
      AppFeatureConfigService.instance.messageFor(featureKey),
    );
    return false;
  }

  return true;
}

Future<bool> ensureBookingPaymentEnabled(
  BuildContext context,
  RentalType rentalType, {
  bool forceRefresh = true,
}) async {
  final maintenance = await AppMaintenanceService.instance.current(
    force: forceRefresh,
  );
  if (maintenance.enabled) {
    if (!context.mounted) return false;
    await _showBlockDialog(context, maintenance.message);
    return false;
  }

  await AppFeatureConfigService.instance.fetch(force: forceRefresh);
  final service = AppFeatureConfigService.instance;

  if (!service.isEnabled(AppFeatureKeys.payment)) {
    if (!context.mounted) return false;
    await _showBlockDialog(
      context,
      service.messageFor(AppFeatureKeys.payment),
    );
    return false;
  }

  final bookingKey = bookingFeatureKeyFor(rentalType);
  if (!service.isEnabled(bookingKey)) {
    if (!context.mounted) return false;
    await _showBlockDialog(context, service.messageFor(bookingKey));
    return false;
  }

  return true;
}

@visibleForTesting
Future<void> showFeatureBlockDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        featureBlockDialogTitle,
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        message,
        style: const TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            popScreenAfterFeatureBlock(context);
          },
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 다이얼로그 확인 후 — 푸시된 화면이면 이전(홈)으로, 루트면 유지
@visibleForTesting
void popScreenAfterFeatureBlock(BuildContext context) {
  if (!context.mounted) return;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  }
}

Future<void> _showBlockDialog(BuildContext context, String message) =>
    showFeatureBlockDialog(context, message);
