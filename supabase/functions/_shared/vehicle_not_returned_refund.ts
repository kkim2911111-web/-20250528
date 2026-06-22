import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario } from './push_scenarios.ts';
import { cancelTossPayment } from './toss.ts';
import { paymentOrderCancelledUpdate } from './payment_order_status.ts';

type ReservationRow = {
  id: string;
  user_id: string;
  status: string;
  cancel_reason?: string | null;
  refund_amount?: number | null;
  payment_key?: string | null;
  order_id?: string | null;
  vehicle_id?: string | number | null;
  vehicles?: { complex_id?: string; model_name?: string } | null;
};

export type VehicleNotReturnedRefundResult = {
  ok: boolean;
  alreadyRefunded?: boolean;
  refundAmount?: number;
  paidAmount?: number;
  skipped?: boolean;
  error?: string;
};

async function fetchRenterName(
  admin: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data: profile } = await admin
    .from('user_profiles')
    .select('full_name')
    .eq('user_id', userId)
    .maybeSingle();

  const name = profile?.full_name?.toString()?.trim();
  return name && name.length > 0 ? name : '임차인';
}

async function hasSentPush(
  admin: SupabaseClient,
  reservationId: string,
): Promise<boolean> {
  const { data } = await admin
    .from('push_reminder_log')
    .select('id')
    .eq('reservation_id', reservationId)
    .eq('scenario', 'vehicle_not_returned_auto_refund')
    .maybeSingle();
  return !!data;
}

async function markSentPush(
  admin: SupabaseClient,
  reservationId: string,
): Promise<void> {
  await admin.from('push_reminder_log').insert({
    reservation_id: reservationId,
    scenario: 'vehicle_not_returned_auto_refund',
  });
}

async function notifyVehicleNotReturned(
  admin: SupabaseClient,
  params: {
    reservationId: string;
    userId: string;
    vehicleName: string;
    complexId: string | null;
    renterName: string;
  },
): Promise<void> {
  if (await hasSentPush(admin, params.reservationId)) return;

  await dispatchPushScenario({
    admin,
    scenario: 'customer_vehicle_not_returned_refund',
    payload: {
      userId: params.userId,
      reservationId: params.reservationId,
      vehicleName: params.vehicleName,
    },
  });

  if (params.complexId) {
    await dispatchPushScenario({
      admin,
      scenario: 'staff_vehicle_not_returned_auto',
      payload: {
        complexId: params.complexId,
        reservationId: params.reservationId,
        vehicleName: params.vehicleName,
        renterName: params.renterName,
      },
    });
  }

  await markSentPush(admin, params.reservationId);
}

export async function processVehicleNotReturnedRefund(
  admin: SupabaseClient,
  reservationId: string,
  options?: { sendPush?: boolean },
): Promise<VehicleNotReturnedRefundResult> {
  const id = reservationId?.toString()?.trim();
  if (!id) {
    return { ok: false, error: 'reservationId 가 필요합니다.' };
  }

  const { data: reservation, error } = await admin
    .from('reservations')
    .select(
      'id, user_id, status, cancel_reason, refund_amount, payment_key, order_id, vehicle_id, vehicles(complex_id, model_name)',
    )
    .eq('id', id)
    .maybeSingle();

  if (error || !reservation) {
    return { ok: false, error: '예약을 찾을 수 없습니다.' };
  }

  const row = reservation as ReservationRow;

  if (row.status !== 'cancelled' || row.cancel_reason !== 'vehicle_not_returned') {
    return { ok: false, error: '차량미회수 취소 상태가 아닙니다.' };
  }

  if (Number(row.refund_amount ?? 0) > 0) {
    return {
      ok: true,
      alreadyRefunded: true,
      refundAmount: Number(row.refund_amount),
    };
  }

  const { data: paidRaw, error: paidErr } = await admin.rpc(
    'reservation_card_paid_amount',
    { p_reservation_id: id },
  );
  if (paidErr) {
    return { ok: false, error: paidErr.message };
  }

  const paid = Number(paidRaw ?? 0);
  if (!Number.isFinite(paid) || paid < 0) {
    return { ok: false, error: '결제 금액을 확인할 수 없습니다.' };
  }

  if (paid > 0) {
    const paymentKey = row.payment_key?.toString()?.trim();
    if (!paymentKey) {
      return { ok: false, error: '결제 키가 없어 환불할 수 없습니다.' };
    }

    try {
      await cancelTossPayment({
        paymentKey,
        cancelReason: '앞 예약 미반납으로 이용 불가',
        cancelAmount: paid,
      });
    } catch (e) {
      const err = e as Error;
      console.error('[vehicle_not_returned_refund] toss', err);
      return { ok: false, error: err.message || '토스 환불 실패' };
    }
  }

  const { data: finalizeRaw, error: finalizeErr } = await admin.rpc(
    'finalize_vehicle_not_returned_refund_for_service',
    {
      p_reservation_id: id,
      p_refund_amount: paid,
    },
  );

  if (finalizeErr) {
    return { ok: false, error: finalizeErr.message };
  }

  const finalize = (finalizeRaw ?? {}) as Record<string, unknown>;
  if (finalize.restoreBenefits === true) {
    try {
      await admin.rpc('restore_booking_benefits_after_cancel', {
        p_user_id: row.user_id,
        p_reservation_id: id,
        p_restore_benefits: true,
      });
    } catch (restoreErr) {
      console.error('[vehicle_not_returned_refund] benefit restore', restoreErr);
    }
  }

  const vehicleRaw = row.vehicles as {
    complex_id?: string;
    model_name?: string;
  } | null;
  const vehicleName = vehicleRaw?.model_name?.toString()?.trim() || '차량';
  const complexId = vehicleRaw?.complex_id?.toString() ?? null;

  if (options?.sendPush !== false) {
    try {
      const renterName = await fetchRenterName(admin, row.user_id);
      await notifyVehicleNotReturned(admin, {
        reservationId: id,
        userId: row.user_id,
        vehicleName,
        complexId,
        renterName,
      });
    } catch (pushErr) {
      console.error('[vehicle_not_returned_refund] push', pushErr);
    }
  }

  return {
    ok: true,
    refundAmount: paid,
    paidAmount: paid,
  };
}
