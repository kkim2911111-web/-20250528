import { confirmTossPayment } from '../lib/toss.js';
import { cors, getSupabaseAdmin, getUserFromRequest, json } from '../lib/supabase.js';

async function hasOverlap(admin, vehicleId, startTime, endTime) {
  const pairs = [
    ['start_time', 'end_time'],
    ['start_at', 'end_at'],
  ];
  for (const [startCol, endCol] of pairs) {
    const { data, error } = await admin
      .from('reservations')
      .select('id')
      .eq('vehicle_id', String(vehicleId))
      .in('status', ['pending', 'confirmed'])
      .lt(startCol, endTime)
      .gt(endCol, startTime)
      .limit(1);
    if (!error && data?.length) return true;
    if (error && !error.message?.includes('column')) continue;
  }
  return false;
}

async function createReservation(admin, order) {
  const base = {
    user_id: order.user_id,
    vehicle_id: String(order.vehicle_id),
    total_price: order.total_price,
    status: 'confirmed',
    payment_key: order.payment_key,
    order_id: order.order_id,
    payment_status: 'paid',
  };

  const variants = [
    { ...base, start_time: order.start_time, end_time: order.end_time },
    { ...base, start_at: order.start_time, end_at: order.end_time },
    {
      user_id: base.user_id,
      vehicle_id: base.vehicle_id,
      start_time: order.start_time,
      end_time: order.end_time,
      total_price: base.total_price,
      status: 'confirmed',
    },
  ];

  let lastError;
  for (const payload of variants) {
    const { data, error } = await admin
      .from('reservations')
      .insert(payload)
      .select('id')
      .single();
    if (!error) return data.id;
    lastError = error;
    if (error.code !== 'PGRST204' && !error.message?.includes('column')) {
      break;
    }
  }
  throw lastError || new Error('reservations insert failed');
}

export default async function handler(req, res) {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  try {
    const user = await getUserFromRequest(req);
    if (!user) return json(res, 401, { error: 'Unauthorized' });

    const { paymentKey, orderId, amount } = req.body || {};
    if (!paymentKey || !orderId || amount == null) {
      return json(res, 400, { error: 'paymentKey, orderId, amount 가 필요합니다.' });
    }

    const admin = getSupabaseAdmin();

    const { data: order, error: orderError } = await admin
      .from('payment_orders')
      .select('*')
      .eq('order_id', orderId)
      .eq('user_id', user.id)
      .maybeSingle();

    if (orderError || !order) {
      return json(res, 404, { error: '주문을 찾을 수 없습니다.' });
    }

    if (order.status === 'paid') {
      return json(res, 200, {
        ok: true,
        reservationId: order.reservation_id,
        alreadyPaid: true,
      });
    }

    if (order.status !== 'pending') {
      return json(res, 400, { error: '결제할 수 없는 주문 상태입니다.' });
    }

    if (Number(order.total_price) !== Number(amount)) {
      return json(res, 400, { error: '결제 금액이 일치하지 않습니다.' });
    }

    const overlap = await hasOverlap(
      admin,
      order.vehicle_id,
      order.start_time,
      order.end_time,
    );
    if (overlap) {
      await admin
        .from('payment_orders')
        .update({
          status: 'cancelled',
          updated_at: new Date().toISOString(),
        })
        .eq('order_id', orderId);
      return json(res, 409, { error: '이미 예약된 시간입니다.' });
    }

    const tossResult = await confirmTossPayment({
      paymentKey,
      orderId,
      amount: Number(amount),
    });

    order.payment_key = paymentKey;
    const reservationId = await createReservation(admin, order);

    await admin
      .from('payment_orders')
      .update({
        status: 'paid',
        payment_key: paymentKey,
        has_payment_key: true,
        reservation_id: reservationId,
        updated_at: new Date().toISOString(),
      })
      .eq('order_id', orderId);

    return json(res, 200, {
      ok: true,
      reservationId,
      payment: tossResult,
    });
  } catch (e) {
    const admin = getSupabaseAdmin();
    const orderId = req.body?.orderId;
    if (orderId) {
      await admin
        .from('payment_orders')
        .update({
          status: 'failed',
          updated_at: new Date().toISOString(),
        })
        .eq('order_id', orderId);
    }
    return json(res, 500, {
      error: e.message || '결제 승인 실패',
      code: e.code,
    });
  }
}
