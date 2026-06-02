import { handleCors, jsonResponse } from '../_shared/http.ts';
import {
  getAdminClient,
  getUserFromRequest,
  hasOverlap,
} from '../_shared/payment.ts';
import { confirmTossPayment } from '../_shared/toss.ts';
import { sendReservationCompletePush } from '../_shared/fcm.ts';
import {
  PaymentOrderStatus,
  isPaymentOrderPaid,
  paymentOrderCancelledUpdate,
  paymentOrderFailedUpdate,
  paymentOrderPaidUpdate,
} from '../_shared/payment_order_status.ts';

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

    if (
      isPaymentOrderPaid(order.status) ||
      order.status === PaymentOrderStatus.failed
    ) {
      if (order.reservation_id) {
        return jsonResponse({
          ok: true,
          reservationId: String(order.reservation_id),
          orderId,
          paymentKey: order.payment_key ?? paymentKey,
          alreadyPaid: true,
        });
      }

      const { data: existingRes } = await admin
        .from('reservations')
        .select('id')
        .eq('order_id', orderId)
        .eq('user_id', user.id)
        .maybeSingle();

      if (existingRes?.id) {
        return jsonResponse({
          ok: true,
          reservationId: String(existingRes.id),
          orderId,
          paymentKey: order.payment_key ?? paymentKey,
          alreadyPaid: true,
        });
      }

      // paid/confirmed/failed 이지만 reservations 미생성 — 아래 finalize 로 복구 (토스 재승인 없음)
    } else if (order.status !== PaymentOrderStatus.pending) {
      return jsonResponse({ error: '결제할 수 없는 주문 상태입니다.' }, 400);
    }

    if (Number(order.total_price) !== Number(amount)) {
      return jsonResponse({ error: '결제 금액이 일치하지 않습니다.' }, 400);
    }

    if (order.vehicle_id === 'signup_card') {
      const alreadyApproved =
        isPaymentOrderPaid(order.status) ||
        order.has_payment_key === true ||
        (order.payment_key != null && String(order.payment_key).length > 0);

      let tossResult: unknown = null;
      if (!alreadyApproved) {
        tossResult = await confirmTossPayment({
          paymentKey,
          orderId,
          amount: Number(amount),
        });
        await admin
          .from('payment_orders')
          .update(paymentOrderPaidUpdate(paymentKey))
          .eq('order_id', orderId);
      }

      const cardLast4 =
        (tossResult as { card?: { number?: string } })?.card?.number
          ?.toString()
          .slice(-4) ?? '0000';

      await admin.from('user_profiles').upsert(
        {
          user_id: user.id,
          payment_card_registered: true,
          payment_card_last4: cardLast4,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id' },
      );

      return jsonResponse({
        ok: true,
        signupCard: true,
        orderId,
        paymentKey,
        payment: tossResult,
      });
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
        .update(paymentOrderCancelledUpdate())
        .eq('order_id', orderId);
      return jsonResponse({ error: '이미 예약된 시간입니다.' }, 409);
    }

    const alreadyApproved =
      isPaymentOrderPaid(order.status) ||
      order.has_payment_key === true ||
      (order.payment_key != null && String(order.payment_key).length > 0) ||
      (order.status === PaymentOrderStatus.failed &&
        order.payment_key != null &&
        String(order.payment_key).length > 0);

    let tossResult: unknown = null;
    if (!alreadyApproved) {
      console.log('[payment-confirm] calling Toss confirm API', {
        orderId,
        amount: Number(amount),
        paymentKey: `${String(paymentKey).slice(0, 12)}...`,
      });
      tossResult = await confirmTossPayment({
        paymentKey,
        orderId,
        amount: Number(amount),
      });
      console.log('[payment-confirm] Toss confirm succeeded for orderId:', orderId);

      await admin
        .from('payment_orders')
        .update(paymentOrderPaidUpdate(paymentKey))
        .eq('order_id', orderId);
    } else {
      console.log(
        '[payment-confirm] skip Toss confirm — order already approved:',
        orderId,
        order.status,
      );
    }

    let reservationId: string | undefined;

    try {
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

      reservationId = finalized?.reservationId as string | undefined;
    } catch (finalizeErr) {
      // 토스 승인은 완료 — confirmed 유지 후 클라이언트 RPC 재시도 가능
      await admin
        .from('payment_orders')
        .update(paymentOrderPaidUpdate(paymentKey))
        .eq('order_id', orderId);
      throw finalizeErr;
    }

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
    const err = e as Error & { code?: string };
    // 토스 승인 전 오류만 failed (토스 승인 후 finalize 실패는 위에서 처리)
    if (orderId) {
      const admin = getAdminClient();
      const { data: order } = await admin
        .from('payment_orders')
        .select('status, payment_key')
        .eq('order_id', orderId)
        .maybeSingle();
      if (order?.status === PaymentOrderStatus.pending) {
        await admin
          .from('payment_orders')
          .update(paymentOrderFailedUpdate())
          .eq('order_id', orderId);
      }
    }

    return jsonResponse(
      { error: err.message || '결제 승인 실패', code: err.code },
      500,
    );
  }
});
