import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 입체감 버튼 — 하단 그림자 + 눌림 시 translateY
class Danji3dButton extends StatefulWidget {
  final Color backgroundColor;
  final Color shadowColor;
  final double height;
  final double shadowDepth;
  final double pressOffset;
  final BorderRadius borderRadius;
  final VoidCallback? onPressed;
  final bool enabled;
  final Widget child;

  const Danji3dButton({
    super.key,
    required this.backgroundColor,
    required this.shadowColor,
    required this.child,
    this.height = 52,
    this.shadowDepth = 6,
    this.pressOffset = 4,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.onPressed,
    this.enabled = true,
  });

  /// 문열림 스타일
  factory Danji3dButton.unlock({
    Key? key,
    required Widget child,
    VoidCallback? onPressed,
    bool enabled = true,
    double height = 52,
    BorderRadius? borderRadius,
  }) {
    return Danji3dButton(
      key: key,
      backgroundColor: DanjiColors.brandBlue,
      shadowColor: DanjiColors.brandBlueShadow,
      onPressed: onPressed,
      enabled: enabled,
      height: height,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(14)),
      child: child,
    );
  }

  /// 문닫힘 스타일
  factory Danji3dButton.lock({
    Key? key,
    required Widget child,
    VoidCallback? onPressed,
    bool enabled = true,
    double height = 52,
    BorderRadius? borderRadius,
  }) {
    return Danji3dButton(
      key: key,
      backgroundColor: DanjiColors.toneRed,
      shadowColor: DanjiColors.dangerBrightDark,
      onPressed: onPressed,
      enabled: enabled,
      height: height,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(14)),
      child: child,
    );
  }

  /// 반납하기 등 메인 액션
  factory Danji3dButton.primary({
    Key? key,
    required Widget child,
    VoidCallback? onPressed,
    bool enabled = true,
    double height = 60,
    BorderRadius? borderRadius,
  }) {
    return Danji3dButton(
      key: key,
      backgroundColor: DanjiColors.brandBlue,
      shadowColor: DanjiColors.brandBlueShadow,
      onPressed: onPressed,
      enabled: enabled,
      height: height,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(16)),
      child: child,
    );
  }

  @override
  State<Danji3dButton> createState() => _Danji3dButtonState();
}

class _Danji3dButtonState extends State<Danji3dButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pressed && widget.enabled;
    final bg = widget.enabled ? widget.backgroundColor : DanjiColors.textMuted;
    final shadow = widget.enabled ? widget.shadowColor : DanjiColors.textMuted;

    return Padding(
      padding: EdgeInsets.only(bottom: pressed ? 0 : widget.shadowDepth),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: widget.enabled
            ? (_) {
                _setPressed(false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOut,
          height: widget.height,
          transform: Matrix4.translationValues(
            0,
            pressed ? widget.pressOffset : 0,
            0,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: widget.borderRadius,
            boxShadow: pressed
                ? null
                : [
                    BoxShadow(
                      color: shadow,
                      offset: Offset(0, widget.shadowDepth),
                      blurRadius: 0,
                      spreadRadius: 0,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
