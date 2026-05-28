import { cors, getSupabaseAdmin, getUserFromRequest, json } from '../lib/supabase.js';

function makeOrderId() {
  return `danji_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

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

export default async function handler(req, res) {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  try {
    const user = await getUserFromRequest(req);
    if (!user) return json(res, 401, { error: 'Unauthorized' });

    const body = req.body || {};
    const {
      vehicleId,
      vehicleName,
      startTime,
      endTime,
      totalPrice,
    } = body;

    if (!vehicleId || !startTime || !endTime || !totalPrice) {
      return json(res, 400, { error: '필수 값이 누락되었습니다.' });
    }

    const amount = Number(totalPrice);
    if (!Number.isFinite(amount) || amount <= 0) {
      return json(res, 400, { error: '결제 금액이 올바르지 않습니다.' });
    }

    const admin = getSupabaseAdmin();

    const { data: resident } = await admin
      .from('residents')
      .select('complex_id, approved')
      .eq('user_id', user.id)
      .maybeSingle();

    if (!resident?.approved) {
      return json(res, 403, { error: '승인된 입주민만 예약할 수 있습니다.' });
    }

    const { data: vehicle } = await admin
      .from('vehicles')
      .select('id, complex_id, model_name')
      .eq('id', vehicleId)
      .maybeSingle();

    if (!vehicle || String(vehicle.complex_id) !== String(resident.complex_id)) {
      return json(res, 403, { error: '내 단지 차량만 예약할 수 있습니다.' });
    }

    const overlap = await hasOverlap(admin, vehicleId, startTime, endTime);
    if (overlap) {
      return json(res, 409, { error: '이미 예약된 시간입니다.' });
    }

    const orderId = makeOrderId();
    const orderName = `${vehicleName || vehicle.model_name || '단지카'} 예약`;

    const { error: insertError } = await admin.from('payment_orders').insert({
      order_id: orderId,
      user_id: user.id,
      vehicle_id: String(vehicleId),
      vehicle_name: vehicleName || vehicle.model_name,
      start_time: startTime,
      end_time: endTime,
      total_price: amount,
      status: 'pending',
    });

    if (insertError) {
      return json(res, 500, { error: insertError.message });
    }

    return json(res, 200, {
      orderId,
      amount,
      orderName,
      customerKey: user.id,
    });
  } catch (e) {
    return json(res, 500, { error: e.message || 'Internal error' });
  }
}
