import { handleCors, jsonResponse } from '../_shared/http.ts';
import { assertResidentMaintenanceAllowed } from '../_shared/maintenance_mode.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';
import { issueTossBillingKey } from '../_shared/toss.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const user = await getUserFromRequest(req);
    if (!user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const body = await req.json();
    const authKey = body?.authKey?.toString()?.trim();
    const customerKey = body?.customerKey?.toString()?.trim();

    if (!authKey || !customerKey) {
      return jsonResponse({ error: 'authKey, customerKey 가 필요합니다.' }, 400);
    }

    if (customerKey !== user.id) {
      return jsonResponse({ error: 'customerKey 불일치' }, 403);
    }

    const admin = getAdminClient();
    try {
      await assertResidentMaintenanceAllowed(admin, user.id);
    } catch (e) {
      const err = e as Error & { code?: string };
      if (err.code === 'maintenance_active') {
        return jsonResponse(
          { error: 'maintenance_active', code: 'maintenance_active' },
          503,
        );
      }
      throw e;
    }

    const toss = await issueTossBillingKey({ authKey, customerKey });
    const billingKey = toss.billingKey;
    if (!billingKey) {
      return jsonResponse({ error: '빌링키를 받지 못했습니다.' }, 500);
    }

    const cardNumber = toss.card?.number?.toString() ?? '';
    const last4 = cardNumber.length >= 4
      ? cardNumber.slice(-4)
      : '0000';

    await admin.from('user_profiles').upsert(
      {
        user_id: user.id,
        toss_billing_key: billingKey,
        payment_card_registered: true,
        payment_card_last4: last4,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id' },
    );

    return jsonResponse({
      ok: true,
      billingKey,
      cardLast4: last4,
    });
  } catch (e) {
    const err = e as Error & { code?: string };
    console.error('[billing-key-issue]', err);
    return jsonResponse(
      { error: err.message || '빌링키 발급 실패', code: err.code },
      500,
    );
  }
});
