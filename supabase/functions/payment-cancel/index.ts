import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const user = await getUserFromRequest(req);
    if (!user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const { orderId, code, message } = await req.json();
    if (!orderId) return jsonResponse({ error: 'orderId 가 필요합니다.' }, 400);

    const admin = getAdminClient();

    const { data: order } = await admin
      .from('payment_orders')
      .select('status')
      .eq('order_id', orderId)
      .eq('user_id', user.id)
      .maybeSingle();

    if (!order) return jsonResponse({ error: '주문을 찾을 수 없습니다.' }, 404);

    if (order.status === 'paid') {
      return jsonResponse({ ok: true, cancelled: false });
    }

    await admin
      .from('payment_orders')
      .update({
        status: 'cancelled',
        updated_at: new Date().toISOString(),
      })
      .eq('order_id', orderId)
      .eq('user_id', user.id);

    return jsonResponse({
      ok: true,
      cancelled: true,
      code: code ?? null,
      message: message ?? null,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Internal error';
    return jsonResponse({ error: message }, 500);
  }
});
