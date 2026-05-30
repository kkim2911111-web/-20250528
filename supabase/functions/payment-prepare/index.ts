import { handleCors, jsonResponse } from '../_shared/http.ts';
import {
  getAdminClient,
  getUserFromRequest,
  hasOverlap,
  makeOrderId,
} from '../_shared/payment.ts';
import { PaymentOrderStatus } from '../_shared/payment_order_status.ts';

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
    const { vehicleId, vehicleName, startTime, endTime, totalPrice } = body;

    if (!vehicleId || !startTime || !endTime || totalPrice == null) {
      return jsonResponse({ error: '필수 값이 누락되었습니다.' }, 400);
    }

    const amount = Number(totalPrice);
    if (!Number.isFinite(amount) || amount <= 0) {
      return jsonResponse({ error: '결제 금액이 올바르지 않습니다.' }, 400);
    }

    const admin = getAdminClient();

    const { data: resident } = await admin
      .from('residents')
      .select('complex_id, approved')
      .eq('user_id', user.id)
      .maybeSingle();

    if (!resident?.approved) {
      return jsonResponse({ error: '승인된 입주민만 예약할 수 있습니다.' }, 403);
    }

    const { data: vehicle } = await admin
      .from('vehicles')
      .select('id, complex_id, model_name')
      .eq('id', vehicleId)
      .maybeSingle();

    if (
      !vehicle ||
      String(vehicle.complex_id) !== String(resident.complex_id)
    ) {
      return jsonResponse({ error: '내 단지 차량만 예약할 수 있습니다.' }, 403);
    }

    if (await hasOverlap(admin, vehicleId, startTime, endTime)) {
      return jsonResponse({ error: '이미 예약된 시간입니다.' }, 409);
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
      status: PaymentOrderStatus.pending,
    });

    if (insertError) {
      return jsonResponse({ error: insertError.message }, 500);
    }

    return jsonResponse({
      orderId,
      amount,
      orderName,
      customerKey: user.id,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Internal error';
    return jsonResponse({ error: message }, 500);
  }
});
