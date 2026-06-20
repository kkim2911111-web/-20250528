import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

Future<bool> showLogoutConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '로그아웃',
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: const Text(
        '로그아웃 하시겠습니까?',
        style: TextStyle(color: DanjiColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: DanjiColors.accentRed,
            foregroundColor: Colors.white,
          ),
          child: const Text('로그아웃'),
        ),
      ],
    ),
  ).then((value) => value == true);
}
