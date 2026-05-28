const TOSS_API = 'https://api.tosspayments.com/v1';

export async function confirmTossPayment({ paymentKey, orderId, amount }) {
  const secretKey = process.env.TOSS_SECRET_KEY;
  if (!secretKey) {
    throw new Error('TOSS_SECRET_KEY 환경변수가 필요합니다.');
  }

  const auth = Buffer.from(`${secretKey}:`).toString('base64');
  const res = await fetch(`${TOSS_API}/payments/confirm`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ paymentKey, orderId, amount }),
  });

  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data.message || '토스 결제 승인 실패');
    err.code = data.code;
    err.toss = data;
    throw err;
  }
  return data;
}
