const TOSS_API = 'https://api.tosspayments.com/v1';

function getTossAuth(): string {
  const secretKey = Deno.env.get('TOSS_SECRET_KEY');
  if (!secretKey) {
    throw new Error('TOSS_SECRET_KEY 시크릿이 설정되지 않았습니다.');
  }
  return btoa(`${secretKey}:`);
}

/** 웹훅 검증용 — paymentKey로 토스 결제 조회 */
export async function getTossPayment(paymentKey: string) {
  const auth = getTossAuth();
  const url = `${TOSS_API}/payments/${encodeURIComponent(paymentKey)}`;

  const res = await fetch(url, {
    headers: { Authorization: `Basic ${auth}` },
  });

  const data = await res.json();
  console.log('[toss] GET', url, 'response status:', res.status);
  if (!res.ok) {
    const err = new Error(data.message || '토스 결제 조회 실패') as Error & {
      code?: string;
    };
    err.code = data.code;
    throw err;
  }
  return data as {
    paymentKey: string;
    orderId: string;
    status: string;
    totalAmount: number;
    secret?: string;
  };
}

export async function confirmTossPayment(params: {
  paymentKey: string;
  orderId: string;
  amount: number;
}) {
  const auth = getTossAuth();
  const url = `${TOSS_API}/payments/confirm`;
  const body = JSON.stringify(params);

  console.log('[toss] POST', url, 'request:', body);

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body,
  });

  const data = await res.json();
  console.log(
    '[toss] POST',
    url,
    'response status:',
    res.status,
    'body:',
    JSON.stringify(data),
  );
  if (!res.ok) {
    const code = data.code as string | undefined;
    if (
      res.status === 400 &&
      (code === 'ALREADY_PROCESSED_PAYMENT' ||
        code === 'NOT_FOUND_PAYMENT_SESSION')
    ) {
      console.log('[toss] payment already confirmed, treating as success:', code);
      return data;
    }
    const err = new Error(data.message || '토스 결제 승인 실패') as Error & {
      code?: string;
    };
    err.code = code;
    throw err;
  }
  return data;
}

/** 빌링키 발급 — authKey 교환 (실결제 없음) */
export async function issueTossBillingKey(params: {
  authKey: string;
  customerKey: string;
}) {
  const auth = getTossAuth();
  const url = `${TOSS_API}/billing/authorizations/issue`;
  const body = JSON.stringify({
    authKey: params.authKey,
    customerKey: params.customerKey,
  });

  console.log('[toss] POST', url, 'billing issue');

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body,
  });

  const data = await res.json();
  console.log('[toss] billing issue response:', res.status, JSON.stringify(data));
  if (!res.ok) {
    const err = new Error(data.message || '빌링키 발급 실패') as Error & {
      code?: string;
    };
    err.code = data.code;
    throw err;
  }

  return data as {
    billingKey: string;
    card?: { number?: string; cardType?: string };
    method?: string;
  };
}

/** 빌링키로 자동 결제 (연장 등) */
export async function chargeTossBilling(params: {
  billingKey: string;
  customerKey: string;
  amount: number;
  orderId: string;
  orderName: string;
}) {
  const auth = getTossAuth();
  const url = `${TOSS_API}/billing/${encodeURIComponent(params.billingKey)}`;
  const body = JSON.stringify({
    customerKey: params.customerKey,
    amount: params.amount,
    orderId: params.orderId,
    orderName: params.orderName,
    taxFreeAmount: 0,
  });

  console.log('[toss] POST', url, 'billing charge', params.orderId);

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body,
  });

  const data = await res.json();
  console.log(
    '[toss] billing charge response:',
    res.status,
    JSON.stringify(data),
  );
  if (!res.ok) {
    const err = new Error(data.message || '빌링 자동결제 실패') as Error & {
      code?: string;
    };
    err.code = data.code;
    throw err;
  }

  return data as {
    paymentKey: string;
    orderId: string;
    status: string;
    totalAmount: number;
  };
}

export async function cancelTossPayment(params: {
  paymentKey: string;
  cancelReason: string;
  cancelAmount?: number;
}) {
  const auth = getTossAuth();
  const body: Record<string, unknown> = {
    cancelReason: params.cancelReason,
  };
  if (params.cancelAmount != null) {
    body.cancelAmount = params.cancelAmount;
  }

  const res = await fetch(
    `${TOSS_API}/payments/${encodeURIComponent(params.paymentKey)}/cancel`,
    {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );

  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data.message || '토스 결제 취소 실패') as Error & {
      code?: string;
    };
    err.code = data.code;
    throw err;
  }
  return data;
}
