import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { getTossPayment } from '../_shared/toss.ts';
import { sendReservationCompletePush } from '../_shared/fcm.ts';
import {
  isPaymentOrderPaid,
  paymentOrderCancelledUpdate,
  paymentOrderFailedUpdate,
  paymentOrderPaidUpdate,
} from '../_shared/payment_order_status.ts';

function assertServiceCaller(req: Request) {
  const auth = req.headers.get('Authorization');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (serviceKey && auth === `Bearer ${serviceKey}`) return;
  throw new Error('Unauthorized');
}

type WebhookBody = {
  eventType?: string;
  createdAt?: string;
  data?: {
    paymentKey?: string;
    orderId?: string;
    status?: string;
    secret?: string;
    totalAmount?: number;
  };
};

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    assertServiceCaller(req);

    const body = (await req.json()) as WebhookBody;
    if (body.eventType !== 'PAYMENT_STATUS_CHANGED') {
      return jsonResponse({ ok: true, skipped: true, eventType: body.eventType });
    }

    const paymentKey = body.data?.paymentKey;
    const orderId = body.data?.orderId;
    if (!paymentKey || !orderId) {
      return jsonResponse({ error: 'paymentKey, orderId 가 필요합니다.' }, 400);
    }

    const tossPayment = await getTossPayment(paymentKey);
    if (tossPayment.orderId !== orderId) {
      return jsonResponse({ error: 'orderId 불일치' }, 400);
    }

    const admin = getAdminClient();
    const { data: order, error: orderError } = await admin
      .from('payment_orders')
      .select('*')
      .eq('order_id', orderId)
      .maybeSingle();

    if (orderError) {
      throw new Error(orderError.message);
    }
    if (!order) {
      return jsonResponse({ ok: true, skipped: true, reason: 'order_not_found' });
    }

    if (Number(tossPayment.totalAmount) !== Number(order.total_price)) {
      return jsonResponse({ error: '결제 금액이 일치하지 않습니다.' }, 400);
    }

    if (
      isPaymentOrderPaid(order.status) &&
      order.reservation_id != null &&
      String(order.reservation_id).length > 0
    ) {
      return jsonResponse({
        ok: true,
        alreadyProcessed: true,
        reservationId: String(order.reservation_id),
      });
    }

    const status = tossPayment.status;

    if (status === 'DONE') {
      await admin
        .from('payment_orders')
        .update(paymentOrderPaidUpdate(paymentKey))
        .eq('order_id', orderId);

      let reservationId: string | undefined;
      try {
        const { data: finalized, error: finalizeError } = await admin.rpc(
          'finalize_reservation_after_payment',
          {
            p_payment_key: paymentKey,
            p_order_id: orderId,
            p_amount: Number(order.total_price),
            p_user_id: order.user_id,
          },
        );

        if (finalizeError) {
          console.error('[payment-webhook] finalize failed:', finalizeError);
          return jsonResponse({
            ok: true,
            paid: true,
            finalizeError: finalizeError.message,
          });
        }

        reservationId = finalized?.reservationId as string | undefined;
      } catch (finalizeErr) {
        const msg = finalizeErr instanceof Error
          ? finalizeErr.message
          : String(finalizeErr);
        console.error('[payment-webhook] finalize exception:', msg);
        return jsonResponse({ ok: true, paid: true, finalizeError: msg });
      }

      try {
        await sendReservationCompletePush({
          admin,
          userId: order.user_id,
          vehicleName: order.vehicle_name || '차량',
        });
      } catch (pushError) {
        console.error('[payment-webhook] FCM push failed:', pushError);
      }

      return jsonResponse({
        ok: true,
        paid: true,
        reservationId,
        orderId,
        paymentKey,
      });
    }

    if (status === 'CANCELED' || status === 'PARTIAL_CANCELED') {
      if (order.status === 'pending') {
        await admin
          .from('payment_orders')
          .update(paymentOrderCancelledUpdate())
          .eq('order_id', orderId);
      }
      return jsonResponse({ ok: true, cancelled: true, orderId });
    }

    if (status === 'ABORTED' || status === 'EXPIRED') {
      if (order.status === 'pending') {
        await admin
          .from('payment_orders')
          .update(paymentOrderFailedUpdate())
          .eq('order_id', orderId);
      }
      return jsonResponse({ ok: true, failed: true, orderId, status });
    }

    return jsonResponse({
      ok: true,
      skipped: true,
      status,
      orderId,
    });
  } catch (e) {
    const err = e as Error & { code?: string };
    console.error('[payment-webhook]', err);
    const status = err.message === 'Unauthorized' ? 401 : 500;
    return jsonResponse(
      { error: err.message || '웹훅 처리 실패', code: err.code },
      status,
    );
  }
});
