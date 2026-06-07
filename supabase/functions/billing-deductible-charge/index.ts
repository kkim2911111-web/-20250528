import { handleCors, jsonResponse } from '../_shared/http.ts';
import { sendPushToUser } from '../_shared/fcm.ts';
import {
  enqueueBillingRetry,
  notifyBillingPaymentFailed,
} from '../_shared/billing_retry.ts';
import {
  getAdminClient,
  getUserFromRequest,
  makeOrderId,
} from '../_shared/payment.ts';
import { cancelTossPayment, chargeTossBilling } from '../_shared/toss.ts';

const DEDUCTIBLE_RETRY_AMOUNT = 500_000;
const MAX_BILLING_RETRIES = 3;

const DEDUCTIBLE_AMOUNT = 500_000;

type ReservationRow = {
  id: string;
  user_id: string;
  vehicle_id: string;
  status: string;
  is_accident: boolean;
  deductible_charged: boolean;
  deductible_waived: boolean;
  start_at?: string | null;
  start_time?: string | null;
  end_at?: string | null;
  end_time?: string | null;
  vehicles?: { complex_id?: string; model_name?: string } | null;
};

async function assertStaffCanCharge(
  admin: ReturnType<typeof getAdminClient>,
  callerId: string,
  reservationId: string,
): Promise<ReservationRow> {
  const { data: profile } = await admin
    .from('user_profiles')
    .select('is_super_admin')
    .eq('user_id', callerId)
    .maybeSingle();

  const isSuperAdmin = profile?.is_super_admin === true;

  const { data: reservation, error } = await admin
    .from('reservations')
    .select(
      'id, user_id, vehicle_id, status, is_accident, deductible_charged, deductible_waived, start_at, start_time, end_at, end_time, vehicles(complex_id, model_name)',
    )
    .eq('id', reservationId)
    .maybeSingle();

  if (error) {
    console.error('[billing-deductible-charge] reservation', error);
    throw new Error(error.message);
  }
  if (!reservation) {
    const err = new Error('예약을 찾을 수 없습니다.') as Error & { code?: string };
    err.code = 'reservation_not_found';
    throw err;
  }

  const row = reservation as ReservationRow;
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

  return row;
}

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
    const reservation = await assertStaffCanCharge(admin, caller.id, reservationId);

    if (reservation.is_accident !== true) {
      return jsonResponse(
        { error: '사고 예약만 면책금을 청구할 수 있습니다.', code: 'not_accident_reservation' },
        400,
      );
    }
    if (reservation.deductible_charged === true) {
      return jsonResponse(
        { error: '이미 면책금이 청구되었습니다.', code: 'deductible_already_charged' },
        400,
      );
    }
    if (reservation.deductible_waived === true) {
      return jsonResponse(
        { error: '면책금이 면제된 예약입니다.', code: 'deductible_waived' },
        400,
      );
    }

    const renterUserId = reservation.user_id?.toString();
    if (!renterUserId) {
      return jsonResponse({ error: '임차인 정보가 없습니다.' }, 400);
    }

    const { data: renterProfile, error: profileErr } = await admin
      .from('user_profiles')
      .select('toss_billing_key, payment_card_registered')
      .eq('user_id', renterUserId)
      .maybeSingle();

    if (profileErr) {
      return jsonResponse({ error: profileErr.message }, 500);
    }

    const billingKey = renterProfile?.toss_billing_key?.toString()?.trim();
    if (!billingKey || renterProfile?.payment_card_registered !== true) {
      return jsonResponse(
        {
          error: '고객에게 등록된 결제카드가 없습니다.',
          code: 'billing_key_missing',
        },
        400,
      );
    }

    const vehicleName =
      reservation.vehicles?.model_name?.toString()?.trim() || '단지카';
    const orderId = `ded_${reservationId}_${makeOrderId()}`;
    const orderName = '면책금';

    let paymentKey: string | null = null;
    try {
      const charge = await chargeTossBilling({
        billingKey,
        customerKey: renterUserId,
        amount: DEDUCTIBLE_AMOUNT,
        orderId,
        orderName,
      });
      paymentKey = charge.paymentKey;
      if (!paymentKey) {
        return jsonResponse({ error: '결제 승인 키를 받지 못했습니다.' }, 500);
      }

      const startTime = reservation.start_at ?? reservation.start_time ?? null;
      const endTime = reservation.end_at ?? reservation.end_time ?? null;

      const { error: orderErr } = await admin.from('payment_orders').insert({
        order_id: orderId,
        user_id: renterUserId,
        vehicle_id: String(reservation.vehicle_id),
        vehicle_name: vehicleName,
        start_time: startTime,
        end_time: endTime,
        total_price: DEDUCTIBLE_AMOUNT,
        status: 'paid',
        payment_key: paymentKey,
        reservation_id: reservationId,
        has_payment_key: true,
      });

      if (orderErr) {
        console.error('[billing-deductible-charge] payment_orders', orderErr);
        try {
          await cancelTossPayment({
            paymentKey,
            cancelReason: '결제 내역 저장 실패',
            cancelAmount: DEDUCTIBLE_AMOUNT,
          });
        } catch (cancelErr) {
          console.error('[billing-deductible-charge] cancel', cancelErr);
        }
        return jsonResponse(
          { error: orderErr.message, code: 'payment_order_save_failed' },
          500,
        );
      }

      const chargedAt = new Date().toISOString();
      const { error: updateErr } = await admin
        .from('reservations')
        .update({
          deductible_charged: true,
          deductible_amount: DEDUCTIBLE_AMOUNT,
          deductible_charged_at: chargedAt,
          deductible_unpaid: false,
          deductible_unpaid_at: null,
          updated_at: chargedAt,
        })
        .eq('id', reservationId)
        .eq('deductible_charged', false);

      if (updateErr) {
        console.error('[billing-deductible-charge] reservation update', updateErr);
        try {
          await cancelTossPayment({
            paymentKey,
            cancelReason: '면책금 상태 저장 실패',
            cancelAmount: DEDUCTIBLE_AMOUNT,
          });
        } catch (cancelErr) {
          console.error('[billing-deductible-charge] cancel', cancelErr);
        }
        return jsonResponse(
          { error: updateErr.message, code: 'deductible_update_failed' },
          400,
        );
      }

      const pushTitle = '면책금 청구 안내';
      const pushBody = '면책금 ₩500,000이 청구되었습니다';

      try {
        await sendPushToUser({
          admin,
          userId: renterUserId,
          title: pushTitle,
          body: pushBody,
          data: {
            type: 'deductible_charged',
            reservation_id: reservationId,
          },
        });
        await admin.from('notifications').insert({
          user_id: renterUserId,
          title: pushTitle,
          body: pushBody,
          type: 'deductible_charged',
          reservation_id: reservationId,
          is_read: false,
        });
      } catch (pushErr) {
        console.error('[billing-deductible-charge] push', pushErr);
      }

      return jsonResponse({
        ok: true,
        amount: DEDUCTIBLE_AMOUNT,
        paymentKey,
        orderId,
        reservationId,
      });
    } catch (chargeErr) {
      const err = chargeErr as Error & { code?: string };
      console.error('[billing-deductible-charge] charge', err);
      if (paymentKey) {
        try {
          await cancelTossPayment({
            paymentKey,
            cancelReason: '면책금 처리 오류',
            cancelAmount: DEDUCTIBLE_AMOUNT,
          });
        } catch (_) {}
      }

      const complexId = reservation.vehicles?.complex_id?.toString() ?? null;
      try {
        await enqueueBillingRetry(admin, {
          chargeType: 'deductible',
          reservationId,
          userId: renterUserId,
          amount: DEDUCTIBLE_RETRY_AMOUNT,
          complexId,
          lastError: err.message || '결제 실패',
        });
        await notifyBillingPaymentFailed(admin, {
          chargeType: 'deductible',
          reservationId,
          userId: renterUserId,
          amount: DEDUCTIBLE_RETRY_AMOUNT,
          complexId,
          retryCount: 0,
          maxRetries: MAX_BILLING_RETRIES,
          isFinal: false,
        });
      } catch (retryErr) {
        console.error('[billing-deductible-charge] retry enqueue', retryErr);
      }

      return jsonResponse(
        {
          error: err.message || '결제에 실패했습니다.',
          code: err.code ?? 'billing_charge_failed',
        },
        402,
      );
    }
  } catch (e) {
    const err = e as Error & { code?: string };
    console.error('[billing-deductible-charge]', err);
    const status = err.code === 'forbidden' ? 403 : err.code === 'reservation_not_found' ? 404 : 500;
    return jsonResponse(
      { error: err.message || '면책금 청구 실패', code: err.code },
      status,
    );
  }
});
