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

    await payment.requestPayment(params);
  }

  window.DanjiToss = {
    requestPayment: requestPayment,
    getOrigin: getOrigin,
  };
})();
