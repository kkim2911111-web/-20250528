import 'package:danjicar_app/screens/support_pages.dart';
import 'package:danjicar_app/utils/cancel_refund_policy.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancelRefundDisplay', () {
    test('refundTierLabel daily tiers', () {
      expect(
        CancelRefundDisplay.refundTierLabel(
          rentalType: RentalType.daily,
          refundRate: 1,
        ),
        '출고 3일(72시간) 전 취소 — 전액 환불',
      );
      expect(
        CancelRefundDisplay.refundTierLabel(
          rentalType: RentalType.daily,
          refundRate: 0.5,
        ),
        '출고 1~3일(24~72시간) 전 취소 — 50% 환불',
      );
      expect(
        CancelRefundDisplay.refundTierLabel(
          rentalType: RentalType.daily,
          refundRate: 0,
        ),
        '출고 1일(24시간) 이내 취소 — 환불 없음',
      );
    });

    test('faqCancelAnswer includes day-hour notation', () {
      expect(CancelRefundDisplay.faqCancelAnswer, contains('3일(72시간)'));
      expect(CancelRefundDisplay.faqCancelAnswer, contains('쿠폰·포인트'));
    });
  });

  testWidgets('waiting guide link navigates to expanded cancel FAQ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Wrap(
              children: [
                const Text(CancelRefundDisplay.waitingGuidePrefix),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FaqScreen(
                          initialExpandedQuestion:
                              CancelRefundDisplay.faqCancelQuestion,
                        ),
                      ),
                    );
                  },
                  child: const Text(CancelRefundDisplay.waitingGuideLink),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(CancelRefundDisplay.waitingGuideLink));
    await tester.pumpAndSettle();

    expect(find.byType(FaqScreen), findsOneWidget);
    expect(find.text(CancelRefundDisplay.faqCancelQuestion), findsOneWidget);
    expect(find.textContaining('3일(72시간)'), findsOneWidget);
  });

  testWidgets('FaqScreen initialExpandedQuestion expands cancel refund item',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FaqScreen(
          initialExpandedQuestion: CancelRefundDisplay.faqCancelQuestion,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(CancelRefundDisplay.faqCancelQuestion), findsOneWidget);
    expect(find.textContaining('카셰어링(시간)'), findsOneWidget);
    expect(find.textContaining('3일(72시간)'), findsOneWidget);
  });
}
