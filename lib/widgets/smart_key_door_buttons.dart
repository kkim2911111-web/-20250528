import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import '../utils/danji_snackbar.dart';

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
      DanjiSnackBar.show(context, unlockTooEarlyMessage);
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
      DanjiSnackBar.show(
        context,
        unlocked
            ? '${reservation.vehicle?.name ?? '차량'} 문이 열렸습니다.'
            : '${reservation.vehicle?.name ?? '차량'} 문이 잠겼습니다.',
      );
    } catch (e) {
      if (!context.mounted) return;
      DanjiSnackBar.show(context, e.toString());
    } finally {
      onLoading?.call(false);
    }
  }
}

/// 문열림/문닫힘 버튼 (가로 배치 — 단일 카드)
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
        _SmartKeyDoorControlCard(
          children: [
            _SmartKeyDoorSegment(
              label: '문 열기',
              icon: Icons.lock_open_rounded,
              enabled: _canUnlock && !_loading,
              loading: _loading,
              onPressed: _onUnlock,
              showRightDivider: true,
            ),
            _SmartKeyDoorSegment(
              label: '문 잠그기',
              icon: Icons.lock_rounded,
              enabled: !_loading,
              loading: _loading,
              onPressed: _onLock,
            ),
          ],
        ),
      ],
    );
  }
}

enum SmartKeyDoorButtonVariant { unlock, lock }

/// 단일 문 제어 버튼 (반납 화면 등)
class SmartKeyDoorButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final SmartKeyDoorButtonVariant variant;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const SmartKeyDoorButton({
    super.key,
    required this.label,
    required this.icon,
    required this.variant,
    required this.enabled,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _SmartKeyDoorControlCard(
      children: [
        _SmartKeyDoorSegment(
          label: label,
          icon: icon,
          enabled: enabled,
          loading: loading,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _SmartKeyDoorControlCard extends StatelessWidget {
  static const _cardHeight = 62.0;
  static const _radius = 12.0;

  final List<Widget> children;

  const _SmartKeyDoorControlCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: DanjiColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: SizedBox(
          height: _cardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SmartKeyDoorSegment extends StatelessWidget {
  static const _iconSize = 21.0;
  static const _labelSize = 12.0;

  final String label;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;
  final bool showRightDivider;

  const _SmartKeyDoorSegment({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onPressed,
    this.showRightDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    final fg = active ? DanjiColors.textPrimary : DanjiColors.textMuted;

    return Expanded(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: active ? onPressed : null,
              splashColor: Colors.black.withValues(alpha: 0.06),
              highlightColor: Colors.black.withValues(alpha: 0.04),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    SizedBox(
                      width: _iconSize,
                      height: _iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  else
                    Icon(icon, size: _iconSize, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w500,
                      fontSize: _labelSize,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showRightDivider)
            Positioned(
              top: 12,
              bottom: 12,
              right: 0,
              child: Container(
                width: 0.5,
                color: DanjiColors.border,
              ),
            ),
        ],
      ),
    );
  }
}
