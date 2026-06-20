import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/theme/danji_colors.dart';
import 'package:danjicar_app/widgets/smart_key_door_buttons.dart';

void main() {
  testWidgets('door buttons use white card on page background with border', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DanjiColors.pageBackground,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: const [
                Expanded(
                  child: SmartKeyDoorButton(
                    label: '문 열기',
                    icon: Icons.lock_open_rounded,
                    variant: SmartKeyDoorButtonVariant.unlock,
                    enabled: true,
                    onPressed: _noop,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: SmartKeyDoorButton(
                    label: '문 잠그기',
                    icon: Icons.lock_rounded,
                    variant: SmartKeyDoorButtonVariant.lock,
                    enabled: true,
                    onPressed: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final inkDecorations = tester
        .widgetList<Ink>(find.byType(Ink))
        .map((w) => w.decoration! as BoxDecoration)
        .toList();

    expect(inkDecorations.length, 2);
    for (final decoration in inkDecorations) {
      expect(decoration.color, DanjiColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final border = decoration.border! as Border;
      expect(border.top.width, 0.5);
      expect(border.top.color, DanjiColors.border);
    }

    expect(find.text('문 열기'), findsOneWidget);
    expect(find.text('문 잠그기'), findsOneWidget);
  });
}

void _noop() {}
