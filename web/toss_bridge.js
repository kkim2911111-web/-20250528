/**
 * Flutter Web ↔ Toss Payments v2 브릿지
 */
(function () {
  function getOrigin() {
    return window.location.origin;
  }

  async function requestPayment(options) {
    if (typeof TossPayments === 'undefined') {
      throw new Error('TossPayments SDK가 로드되지 않았습니다.');
    }

    if (!options.clientKey) {
      throw new Error('TOSS_CLIENT_KEY가 설정되지 않았습니다.');
    }

    var clientKey = options.clientKey;
    var method = options.method || 'CARD';
    var amount = options.amount;
    var orderId = options.orderId;
    var orderName = options.orderName;
    var customerKey = options.customerKey || 'guest';
    var customerEmail = options.customerEmail;
    var customerName = options.customerName;
    var successUrl = options.successUrl || getOrigin() + '/payment/success';
    var failUrl = options.failUrl || getOrigin() + '/payment/fail';

    var tossPayments = TossPayments(clientKey);
    var payment = tossPayments.payment({ customerKey: customerKey });

    var params = {
      method: method,
      amount: { currency: 'KRW', value: amount },
      orderId: orderId,
      orderName: orderName,
      successUrl: successUrl,
      failUrl: failUrl,
      customerEmail: customerEmail,
      customerName: customerName,
    };

    if (method === 'CARD' && options.easyPay === 'KAKAOPAY') {
      params.card = { flowMode: 'DIRECT', easyPay: 'KAKAOPAY' };
    } else if (method === 'CARD') {
      params.card = { flowMode: 'DEFAULT' };
    } else if (method === 'TRANSFER') {
      params.transfer = { cashReceipt: { type: '소득공제' } };
    }

    try {
      await payment.requestPayment(params);
    } catch (err) {
      var msg = err && err.message ? err.message : String(err);
      if (msg.indexOf('알 수 없') >= 0 || msg.toLowerCase().indexOf('unknown') >= 0) {
        throw new Error(
          'TOSS_CLIENT_KEY가 올바르지 않거나 결제 초기화에 실패했습니다. ' +
            '(.env 또는 dart-define 확인) 원인: ' + msg
        );
      }
      throw err;
    }
  }

  async function requestBillingAuth(options) {
    if (typeof TossPayments === 'undefined') {
      throw new Error('TossPayments SDK가 로드되지 않았습니다.');
    }
    if (!options.clientKey) {
      throw new Error('TOSS_CLIENT_KEY가 설정되지 않았습니다.');
    }

    var clientKey = options.clientKey;
    var customerKey = options.customerKey;
    var customerEmail = options.customerEmail;
    var customerName = options.customerName;
    var successUrl =
      options.successUrl || getOrigin() + '/payment/billing-success';
    var failUrl = options.failUrl || getOrigin() + '/payment/billing-fail';

    var tossPayments = TossPayments(clientKey);
    var payment = tossPayments.payment({ customerKey: customerKey });

    await payment.requestBillingAuth({
      method: 'CARD',
      successUrl: successUrl,
      failUrl: failUrl,
      customerEmail: customerEmail,
      customerName: customerName,
    });
  }

  window.DanjiToss = {
    requestPayment: requestPayment,
    requestBillingAuth: requestBillingAuth,
    getOrigin: getOrigin,
  };
})();
