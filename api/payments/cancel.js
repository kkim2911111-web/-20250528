import { cors, getSupabaseAdmin, getUserFromRequest, json } from '../lib/supabase.js';

export default async function handler(req, res) {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  try {
    const user = await getUserFromRequest(req);
    if (!user) return json(res, 401, { error: 'Unauthorized' });

    const { orderId, code, message } = req.body || {};
    if (!orderId) return json(res, 400, { error: 'orderId 가 필요합니다.' });

    const admin = getSupabaseAdmin();

    const { data: order } = await admin
      .from('payment_orders')
      .select('status')
      .eq('order_id', orderId)
      .eq('user_id', user.id)
      .maybeSingle();

    if (!order) return json(res, 404, { error: '주문을 찾을 수 없습니다.' });

    if (order.status === 'paid') {
      return json(res, 200, { ok: true, cancelled: false });
    }

    await admin
      .from('payment_orders')
      .update({
        status: 'cancelled',
        updated_at: new Date().toISOString(),
      })
      .eq('order_id', orderId)
      .eq('user_id', user.id);

    return json(res, 200, {
      ok: true,
      cancelled: true,
      code: code || null,
      message: message || null,
    });
  } catch (e) {
    return json(res, 500, { error: e.message || 'Internal error' });
  }
}
