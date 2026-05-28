import { handleCors, jsonResponse } from '../_shared/http.ts';
import {
  getAdminClient,
  getUserFromRequest,
  hasOverlap,
} from '../_shared/payment.ts';
import { confirmTossPayment } from '../_shared/toss.ts';
import { sendReservationCompletePush } from '../_shared/fcm.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let orderId: string | undefined;

  try {
    const user = await getUserFromRequest(req);
    if (!user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const body = await req.json();
    const { paymentKey, orderId: oid, amount } = body;
    orderId = oid;

    if (!paymentKey || !orderId || amount == null) {
      return jsonResponse(
        { error: 'paymentKey, orderId, amount 가 필요합니다.' },
        400,
      );
    }

    const admin = getAdminClient();

    const { data: order, error: orderError } = await admin
      .from('payment_orders')
      .select('*')
      .eq('order_id', orderId)
      .eq('user_id', user.id)
      .maybeSingle();

    if (orderError || !order) {
      return jsonResponse({ error: '주문을 찾을 수 없습니다.' }, 404);
    }

    if (order.status === 'paid') {
      return jsonResponse({
        ok: true,
        reservationId: order.reservation_id,
        orderId,
        paymentKey: order.payment_key ?? paymentKey,
        alreadyPaid: true,
      });
    }

    if (order.status !== 'pending') {
      return jsonResponse({ error: '결제할 수 없는 주문 상태입니다.' }, 400);
    }

    if (Number(order.total_price) !== Number(amount)) {
      return jsonResponse({ error: '결제 금액이 일치하지 않습니다.' }, 400);
    }

    if (
      await hasOverlap(
        admin,
        order.vehicle_id,
        order.start_time,
        order.end_time,
      )
    ) {
      await admin
        .from('payment_orders')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('order_id', orderId);
      return jsonResponse({ error: '이미 예약된 시간입니다.' }, 409);
    }

    const tossResult = await confirmTossPayment({
      paymentKey,
      orderId,
      amount: Number(amount),
    });

    const { data: finalized, error: finalizeError } = await admin.rpc(
      'finalize_reservation_after_payment',
      {
        p_payment_key: paymentKey,
        p_order_id: orderId,
        p_amount: Number(amount),
        p_user_id: user.id,
      },
    );

    if (finalizeError) {
      throw new Error(finalizeError.message || '예약 저장 실패');
    }

    const reservationId = finalized?.reservationId as string | undefined;

    let pushResult = { sent: 0, skipped: true as boolean | undefined };
    try {
      pushResult = await sendReservationCompletePush({
        admin,
        userId: user.id,
        vehicleName: order.vehicle_name || '차량',
      });
    } catch (pushError) {
      console.error('FCM push failed:', pushError);
    }

    return jsonResponse({
      ok: true,
      reservationId,
      orderId,
      paymentKey,
      payment: tossResult,
      push: pushResult,
    });
  } catch (e) {
    if (orderId) {
      const admin = getAdminClient();
      await admin
        .from('payment_orders')
        .update({ status: 'failed', updated_at: new Date().toISOString() })
        .eq('order_id', orderId);
    }

    const err = e as Error & { code?: string };
    return jsonResponse(
      { error: err.message || '결제 승인 실패', code: err.code },
      500,
    );
  }
});
