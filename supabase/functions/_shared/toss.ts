const TOSS_API = 'https://api.tosspayments.com/v1';

export async function confirmTossPayment(params: {
  paymentKey: string;
  orderId: string;
  amount: number;
}) {
  const secretKey = Deno.env.get('TOSS_SECRET_KEY');
  if (!secretKey) {
    throw new Error('TOSS_SECRET_KEY 시크릿이 설정되지 않았습니다.');
  }

  const auth = btoa(`${secretKey}:`);
  const res = await fetch(`${TOSS_API}/payments/confirm`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(params),
  });

  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data.message || '토스 결제 승인 실패') as Error & {
      code?: string;
    };
    err.code = data.code;
    throw err;
  }
  return data;
}
