import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';

/// 스마트키·홈 공통 — 문열림/문닫힘 제어
class SmartKeyDoorActions {
  static const unlockTooEarlyMessage = '예약 시작 30분 전부터 문열림이 가능합니다.';

  static Future<void> unlock(
    BuildContext context, {
    required Reservation reservation,
    RentalService? service,
    VoidCallback? onSuccess,
    ValueChanged<bool>? onLoading,
  }) async {
    if (!reservation.canUnlockDoor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(unlockTooEarlyMessage)),
      );
      return;
    }
    await setDoor(
      context,
      reservation: reservation,
      unlocked: true,
      service: service,
      onSuccess: onSuccess,
      onLoading: onLoading,
    );
  }

  static Future<void> lock(
    BuildContext context, {
    required Reservation reservation,
    RentalService? service,
    VoidCallback? onSuccess,
    ValueChanged<bool>? onLoading,
  }) async {
    await setDoor(
      context,
      reservation: reservation,
      unlocked: false,
      service: service,
      onSuccess: onSuccess,
      onLoading: onLoading,
    );
  }

  static Future<void> setDoor(
    BuildContext context, {
    required Reservation reservation,
    required bool unlocked,
    RentalService? service,
    VoidCallback? onSuccess,
    ValueChanged<bool>? onLoading,
  }) async {
    onLoading?.call(true);
    try {
      await (service ?? RentalService()).setDoorLock(
        reservationId: reservation.id,
        unlocked: unlocked,
      );
      if (!context.mounted) return;
      onSuccess?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unlocked
                ? '${reservation.vehicle?.name ?? '차량'} 문이 열렸습니다.'
                : '${reservation.vehicle?.name ?? '차량'} 문이 잠겼습니다.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      onLoading?.call(false);
    }
  }
}

/// 문열림/문닫힘 버튼 (가로 배치)
class SmartKeyDoorButtons extends StatefulWidget {
  final Reservation reservation;
  final VoidCallback? onChanged;
  final bool showHint;
  final RentalService? service;

  const SmartKeyDoorButtons({
    super.key,
    required this.reservation,
    this.onChanged,
    this.showHint = true,
    this.service,
  });

  @override
  State<SmartKeyDoorButtons> createState() => _SmartKeyDoorButtonsState();
}

class _SmartKeyDoorButtonsState extends State<SmartKeyDoorButtons> {
  bool _loading = false;

  Reservation get _reservation => widget.reservation;

  bool get _visible => _reservation.status == 'in_use';

  bool get _canUnlock => _reservation.canUnlockDoor;

  Future<void> _onUnlock() async {
    await SmartKeyDoorActions.unlock(
      context,
      reservation: _reservation,
      service: widget.service,
      onSuccess: widget.onChanged,
      onLoading: (v) {
        if (mounted) setState(() => _loading = v);
      },
    );
  }

  Future<void> _onLock() async {
    await SmartKeyDoorActions.lock(
      context,
      reservation: _reservation,
      service: widget.service,
      onSuccess: widget.onChanged,
      onLoading: (v) {
        if (mounted) setState(() => _loading = v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHint && !_canUnlock) ...[
          const Text(
            SmartKeyDoorActions.unlockTooEarlyMessage,
            style: TextStyle(
              color: DanjiColors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: SmartKeyDoorButton(
                label: '문열림',
                icon: Icons.lock_open_rounded,
                color: DanjiColors.rentalBlue,
                enabled: _canUnlock && !_loading,
                loading: _loading,
                onPressed: _onUnlock,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SmartKeyDoorButton(
                label: '문닫힘',
                icon: Icons.lock_rounded,
                color: DanjiColors.accentRed,
                enabled: !_loading,
                loading: _loading,
                onPressed: _onLock,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class SmartKeyDoorButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const SmartKeyDoorButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: enabled && !loading ? onPressed : null,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color.withValues(alpha: 0.9),
                ),
              )
            : Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? color : DanjiColors.textMuted,
          disabledBackgroundColor: DanjiColors.textMuted,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
