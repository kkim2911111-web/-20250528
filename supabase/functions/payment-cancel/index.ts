import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';
import { cancelReservationForUser } from '../_shared/reservation_cancel.ts';

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
    const { orderId, reservationId, code, message } = body;

    const admin = getAdminClient();

    // 확정 예약 취소 + Toss 환불 (TOSS_SECRET_KEY 사용)
    if (reservationId) {
      const result = await cancelReservationForUser({
        admin,
        userId: user.id,
        reservationId,
      });

      return jsonResponse({
        ok: true,
        cancelled: true,
        ...result,
      });
    }

    // 결제 실패/취소 — 미결제 주문만 취소
    if (!orderId) {
      return jsonResponse(
        { error: 'orderId 또는 reservationId 가 필요합니다.' },
        400,
      );
    }

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
    const err = e as Error & { code?: string };
    return jsonResponse(
      { error: err.message || 'Internal error', code: err.code },
      500,
    );
  }
});
