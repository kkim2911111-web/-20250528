import { handleCors, jsonResponse } from '../_shared/http.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';
import { cancelTossPayment } from '../_shared/toss.ts';

type ReservationRow = {
  id: string;
  user_id: string;
  status: string;
  payment_key?: string | null;
  total_price?: number | null;
  order_id?: string | null;
  vehicles?: { complex_id?: string; model_name?: string } | null;
};

async function assertStaffCanCancel(
  admin: ReturnType<typeof getAdminClient>,
  callerId: string,
  reservationId: string,
): Promise<{ row: ReservationRow; isSuperAdmin: boolean }> {
  const { data: profile } = await admin
    .from('user_profiles')
    .select('is_super_admin')
    .eq('user_id', callerId)
    .maybeSingle();

  const isSuperAdmin = profile?.is_super_admin === true;

  const { data: reservation, error } = await admin
    .from('reservations')
    .select(
      'id, user_id, status, payment_key, total_price, order_id, vehicles(complex_id, model_name)',
    )
    .eq('id', reservationId)
    .maybeSingle();

  if (error) {
    console.error('[admin-force-payment-cancel] reservation', error);
    throw new Error(error.message);
  }
  if (!reservation) {
    const err = new Error('예약을 찾을 수 없습니다.') as Error & { code?: string };
    err.code = 'reservation_not_found';
    throw err;
  }

  const row = reservation as ReservationRow;
  if (row.status !== 'confirmed' && row.status !== 'in_use') {
    const err = new Error('취소할 수 없는 예약 상태입니다.') as Error & {
      code?: string;
    };
    err.code = 'invalid_status';
    throw err;
  }

  const complexId = row.vehicles?.complex_id;
  if (!isSuperAdmin) {
    const { data: staff, error: staffErr } = await admin
      .from('staff_users')
      .select('complex_id')
      .eq('user_id', callerId)
      .eq('approved', true)
      .maybeSingle();

    if (staffErr || !staff?.complex_id || staff.complex_id !== complexId) {
      const err = new Error('관리자 권한이 필요합니다.') as Error & { code?: string };
      err.code = 'forbidden';
      throw err;
    }
  }

  return { row, isSuperAdmin };
}

async function resolvePaymentKey(
  admin: ReturnType<typeof getAdminClient>,
  row: ReservationRow,
): Promise<string | null> {
  const direct = row.payment_key?.trim();
  if (direct) return direct;

  if (!row.order_id) return null;

  const { data: order } = await admin
    .from('payment_orders')
    .select('payment_key')
    .eq('order_id', row.order_id)
    .maybeSingle();

  const fromOrder = order?.payment_key?.toString()?.trim();
  return fromOrder || null;
}

/** 관리자 CS 강제결제취소 — Toss 환불 + 예약/결제 취소 + 차량 가용 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const caller = await getUserFromRequest(req);
    if (!caller) return jsonResponse({ error: 'Unauthorized' }, 401);

    const body = await req.json();
    const reservationId = body?.reservationId?.toString()?.trim();
    if (!reservationId) {
      return jsonResponse({ error: 'reservationId 가 필요합니다.' }, 400);
    }

    const admin = getAdminClient();
    const { row: reservation, isSuperAdmin } = await assertStaffCanCancel(
      admin,
      caller.id,
      reservationId,
    );

    const paymentKey = await resolvePaymentKey(admin, reservation);
    let refunded = false;

    if (paymentKey) {
      await cancelTossPayment({
        paymentKey,
        cancelReason: '관리자 강제결제취소',
        cancelAmount: Number(reservation.total_price ?? 0),
      });
      refunded = true;
    }

    const { error: rpcError } = isSuperAdmin
      ? await admin.rpc('force_payment_cancel_reservation_for_super_admin', {
          p_reservation_id: reservationId,
        })
      : await admin.rpc('force_payment_cancel_reservation_for_staff', {
          p_reservation_id: reservationId,
          p_user_id: caller.id,
        });

    if (rpcError) {
      return jsonResponse(
        { error: rpcError.message || '예약 취소 저장 실패' },
        400,
      );
    }

    try {
      await admin.rpc('restore_user_coupon', { p_reservation_id: reservationId });
    } catch (_) {}

    try {
      await admin.rpc('restore_used_points', { p_reservation_id: reservationId });
    } catch (_) {}

    const vehicleName = reservation.vehicles?.model_name?.trim() || '차량';
    const complexId = reservation.vehicles?.complex_id?.toString();

    try {
      await dispatchPushScenario({
        admin,
        scenario: 'customer_reservation_cancelled',
        payload: {
          userId: reservation.user_id,
          reservationId,
          vehicleName,
          reason: '관리자 강제결제취소',
        },
      });
      if (complexId) {
        await dispatchPushScenario({
          admin,
          scenario: 'staff_reservation_cancelled',
          payload: { complexId, reservationId, vehicleName },
        });
      }
    } catch (pushErr) {
      console.error('[admin-force-payment-cancel] push failed:', pushErr);
    }

    return jsonResponse({
      ok: true,
      reservationId,
      cancelled: true,
      refunded,
    });
  } catch (e) {
    const err = e as Error & { code?: string };
    return jsonResponse(
      { error: err.message || 'Internal error', code: err.code },
      500,
    );
  }
});
