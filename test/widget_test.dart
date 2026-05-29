import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/routing/app_routes.dart';

void main() {
  test('routePath strips query string from payment redirect URL', () {
    expect(
      routePath('/payment/success?orderId=abc&paymentKey=pk&amount=1000'),
      '/payment/success',
    );
    expect(routePath('/payment/fail?code=USER_CANCEL'), '/payment/fail');
    expect(routePath('/home'), '/home');
  });

  test('isPaymentSuccessPath detects payment success routes', () {
    expect(isPaymentSuccessPath('/payment/success'), isTrue);
    expect(
      isPaymentSuccessPath('/payment/success?orderId=x'),
      isTrue,
    );
    expect(isPaymentSuccessPath('/home'), isFalse);
  });
}
