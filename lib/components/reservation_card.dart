import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/rental_controller.dart';
import '../models/reservation.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../theme/danji_typography.dart';
import '../models/reservation_payment_pricing.dart';
import '../widgets/reservation_price_display.dart';
import '../widgets/smart_key_door_buttons.dart';

/// 홈·내 예약 공통 예약 카드
class ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final ReservationPaymentPricing? pricing;
  final ReservationCardPhase phase;
  final DateFormat dateFormat;
  final NumberFormat won;
  final RentalController controller;
  final VoidCallback? onRefresh;

  final bool showManageButtons;
  final bool manageActionsEnabled;
  final VoidCallback? onCancelTap;
  final bool showCancelOnly;
  final VoidCallback? onCancelOnlyTap;
  final VoidCallback? onViewHistory;

  const ReservationCard({
    super.key,
    required this.reservation,
    this.pricing,
    required this.phase,
    required this.dateFormat,
    required this.won,
    required this.controller,
    this.onRefresh,
    this.showManageButtons = false,
    this.manageActionsEnabled = true,
    this.onCancelTap,
    this.showCancelOnly = false,
    this.onCancelOnlyTap,
    this.onViewHistory,
  });

  Color get _accentColor {
    switch (phase) {
      case ReservationCardPhase.inRental:
        return DanjiColors.sectionOperating;
      case ReservationCardPhase.beforeRental:
        return DanjiColors.sectionWaiting;
      case ReservationCardPhase.finished:
        return DanjiColors.sectionFinished;
    }
  }

  bool get _showPhotoSection =>
      phase == ReservationCardPhase.beforeRental &&
      !reservation.hasPickupPhotosComplete;

  bool get _showStartActivationHint =>
      phase == ReservationCardPhase.beforeRental &&
      controller.showStartButton(reservation) &&
      controller.isTooEarlyForStart(reservation);

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final start = reservation.startAt;
    final end = reservation.endAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: DanjiRadius.cardBorder,
        border: Border.all(
          color: phase == ReservationCardPhase.finished
              ? DanjiColors.border
              : _accentColor.withValues(alpha: 0.35),
          width: phase == ReservationCardPhase.inRental ? 1.5 : 1,
        ),
        boxShadow: DanjiShadow.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            vehicleName: vehicle?.name ?? '차량',
            statusLabel: reservation.displayStatusLabel,
            accentColor: _accentColor,
            showPulse: phase == ReservationCardPhase.inRental,
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DanjiTypography.secondary.copyWith(height: 1.4),
            ),
            if (phase == ReservationCardPhase.beforeRental) ...[
              const SizedBox(height: 4),
              Text(
                reservation.timeUntilStartLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DanjiColors.buttonBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          if (vehicle?.parkingLocation != null) ...[
            const SizedBox(height: 4),
            Text(
              '주차: ${vehicle!.parkingLocation}',
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (reservation.totalPrice > 0 ||
              (pricing != null && pricing!.finalPrice > 0)) ...[
            const SizedBox(height: 4),
            ReservationPriceDisplay(
              reservationTotalPrice: reservation.totalPrice,
              pricing: pricing,
              won: won,
              priceStyle: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _ActionButtons(
            reservation: reservation,
            phase: phase,
            controller: controller,
            onRefresh: onRefresh,
            onViewHistory: onViewHistory,
          ),
          if (showManageButtons) ...[
            const SizedBox(height: 10),
            _CompactOutlineButton(
              label: '예약취소',
              icon: Icons.event_busy_outlined,
              foregroundColor: DanjiColors.accentRed,
              enabled: manageActionsEnabled,
              onPressed: onCancelTap,
              fullWidth: true,
            ),
            if (!manageActionsEnabled) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: DanjiColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ReservationCancelMessages.tooLate,
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (showCancelOnly && onCancelOnlyTap != null) ...[
            const SizedBox(height: 10),
            _CompactOutlineButton(
              label: '예약취소',
              icon: Icons.event_busy_outlined,
              foregroundColor: DanjiColors.accentRed,
              enabled: manageActionsEnabled,
              onPressed: onCancelOnlyTap,
              fullWidth: true,
            ),
          ],
          if (_showStartActivationHint) ...[
            const SizedBox(height: 8),
            Text(
              RentalStartMessages.startButtonActivationHint,
              style: const TextStyle(
                color: DanjiColors.sectionOperating,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_showPhotoSection) ...[
            const SizedBox(height: 10),
            const Text(
              '대여 전 필수 사진',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              RentalPhotoMessages.dashboardRequiredNote,
              style: TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ] else if (phase == ReservationCardPhase.beforeRental &&
              reservation.hasPickupPhotosComplete) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.check_circle, color: DanjiColors.rentalBlue, size: 16),
                SizedBox(width: 6),
                Text(
                  '사진등록완료',
                  style: TextStyle(
                    color: DanjiColors.rentalBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String vehicleName;
  final String statusLabel;
  final Color accentColor;
  final bool showPulse;

  const _CardHeader({
    required this.vehicleName,
    required this.statusLabel,
    required this.accentColor,
    required this.showPulse,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showPulse)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        Expanded(
          child: Text(
            vehicleName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DanjiTypography.subtitle,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DanjiTypography.caption.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final Reservation reservation;
  final ReservationCardPhase phase;
  final RentalController controller;
  final VoidCallback? onRefresh;
  final VoidCallback? onViewHistory;

  const _ActionButtons({
    required this.reservation,
    required this.phase,
    required this.controller,
    this.onRefresh,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case ReservationCardPhase.beforeRental:
        if (!controller.showStartButton(reservation)) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: controller.canStartRental(reservation)
                ? () async {
                    final ok = await controller.startRental(context, reservation);
                    if (ok == true) onRefresh?.call();
                  }
                : null,
            icon: const Icon(Icons.directions_car_outlined, size: 18),
            label: const Text('대여하기'),
            style: DanjiTheme.primaryButton.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 12),
              ),
              textStyle: WidgetStatePropertyAll(DanjiTypography.buttonPrimary),
            ),
          ),
        );

      case ReservationCardPhase.inRental:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _DoorActionButton(
                    label: '문열림',
                    icon: Icons.lock_open_rounded,
                    color: DanjiColors.rentalBlue,
                    enabled: controller.canUnlockDoor(reservation),
                    onPressed: () => controller.unlockDoor(
                      context,
                      reservation,
                      onChanged: onRefresh,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DoorActionButton(
                    label: '문닫힘',
                    icon: Icons.lock_rounded,
                    color: DanjiColors.accentRed,
                    enabled: true,
                    onPressed: () => controller.lockDoor(
                      context,
                      reservation,
                      onChanged: onRefresh,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: controller.canReturn(reservation)
                    ? () async {
                        final ok =
                            await controller.returnVehicle(context, reservation);
                        if (ok == true) onRefresh?.call();
                      }
                    : null,
                style: DanjiTheme.primaryButton.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44)),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                child: const Text('반납하기'),
              ),
            ),
          ],
        );

      case ReservationCardPhase.finished:
        if (onViewHistory == null) return const SizedBox.shrink();
        return SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            onPressed: onViewHistory,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('대여 내역 보기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DanjiColors.buttonBlue,
              side: BorderSide(
                color: DanjiColors.buttonBlue.withValues(alpha: 0.55),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: DanjiRadius.buttonBorder,
              ),
            ),
          ),
        );
    }
  }
}

class _DoorActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _DoorActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isUnlock = color == DanjiColors.rentalBlue ||
        color == DanjiColors.brandBlue ||
        color == DanjiColors.buttonBlue;

    return SmartKeyDoorButton(
      label: label,
      icon: icon,
      variant: isUnlock
          ? SmartKeyDoorButtonVariant.unlock
          : SmartKeyDoorButtonVariant.lock,
      enabled: enabled,
      onPressed: onPressed,
    );
  }
}

class _CompactOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool fullWidth;

  const _CompactOutlineButton({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.enabled,
    this.onPressed,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? foregroundColor : DanjiColors.textMuted;
    final button = OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 17, color: fg),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(
          color: enabled
              ? foregroundColor.withValues(alpha: 0.55)
              : DanjiColors.border,
        ),
        backgroundColor: DanjiColors.surface,
        padding: const EdgeInsets.symmetric(vertical: 11),
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(
          borderRadius: DanjiRadius.buttonBorder,
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
