import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/reservation.dart';
import 'package:danjicar_app/theme/danji_colors.dart';
import 'package:danjicar_app/widgets/smart_key_door_buttons.dart';

void main() {
  testWidgets('door buttons render unified white card with divider', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DanjiColors.pageBackground,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SmartKeyDoorButtons(
              reservation: Reservation.fromMap({
                'id': '1',
                'user_id': 'u1',
                'vehicle_id': '23',
                'start_time': DateTime.now().toUtc().toIso8601String(),
                'end_time': DateTime.now()
                    .add(const Duration(hours: 1))
                    .toUtc()
                    .toIso8601String(),
                'total_price': 10000,
                'status': 'in_use',
              }),
              showHint: false,
            ),
          ),
        ),
      ),
    );

    final card = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(SmartKeyDoorButtons),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final decoration = card.decoration! as BoxDecoration;

    expect(decoration.color, DanjiColors.surface);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect((decoration.border as Border).top.width, 0.5);
    expect(decoration.boxShadow, isNotEmpty);

    expect(find.text('문 열기'), findsOneWidget);
    expect(find.text('문 잠그기'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
  });
}
