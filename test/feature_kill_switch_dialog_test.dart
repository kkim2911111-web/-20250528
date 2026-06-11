import 'package:danjicar_app/models/app_feature_config.dart';
import 'package:danjicar_app/utils/feature_kill_switch_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('feature block dialog', () {
    test('title is 서비스 점검', () {
      expect(featureBlockDialogTitle, '서비스 점검');
    });

    testWidgets(
      'booking_monthly OFF flow — 서비스 점검 다이얼로그 후 확인 시 홈 복귀',
      (tester) async {
        const homeKey = Key('home');
        const bookingKey = Key('booking');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              key: homeKey,
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          key: bookingKey,
                          body: Builder(
                            builder: (innerContext) => FilledButton(
                              onPressed: () {
                                showFeatureBlockDialog(
                                  innerContext,
                                  AppFeatureConfig.defaultFeatureDisabledMessage,
                                );
                              },
                              child: const Text('예약하기'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('예약 진입'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('예약 진입'));
        await tester.pumpAndSettle();
        expect(find.byKey(bookingKey), findsOneWidget);

        await tester.tap(find.text('예약하기'));
        await tester.pumpAndSettle();

        expect(find.text(featureBlockDialogTitle), findsOneWidget);
        expect(
          find.text(AppFeatureConfig.defaultFeatureDisabledMessage),
          findsOneWidget,
        );

        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();

        expect(find.byKey(homeKey), findsOneWidget);
        expect(find.byKey(bookingKey), findsNothing);
        expect(find.text(featureBlockDialogTitle), findsNothing);
      },
    );
  });
}
