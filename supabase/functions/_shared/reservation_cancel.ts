import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario, resolveComplexId } from './push_scenarios.ts';
import { cancelTossPayment } from './toss.ts';
import { paymentOrderCancelledUpdate } from './payment_order_status.ts';

type CancelRefundQuote = {
  paidAmount: number;
  refundRate: number;
  refundAmount: number;
  refundPercent: number;
  restoreBenefits: boolean;
};

function parseQuote(data: unknown): CancelRefundQuote {
  const row = (data ?? {}) as Record<string, unknown>;
  const refundRate = Number(row.refundRate ?? 0);
  return {
    paidAmount: Number(row.paidAmount ?? 0),
    refundRate,
    refundAmount: Number(row.refundAmount ?? 0),
    refundPercent: Number(row.refundPercent ?? Math.round(refundRate * 100)),
    restoreBenefits: row.restoreBenefits === true,
  };
}

export async function cancelReservationForUser(params: {
  admin: SupabaseClient;
  userId: string;
  reservationId: string;
}) {
  const { admin, userId, reservationId } = params;
  const id = reservationId?.trim();
  if (!id) {
    throw new Error('예약 ID가 없습니다.');
  }

  const { data: reservation, error: reservationError } = await admin
    .from('reservations')
    .select(
      'id, status, start_at, start_time, rental_type, payment_key, payment_status, total_price, order_id, vehicle_id, vehicles(model_name, complex_id)',
    )
    .eq('id', id)
    .eq('user_id', userId)
    .maybeSingle();

  if (reservationError) {
    throw new Error(reservationError.message || '예약 조회 실패');
  }

  if (!reservation) {
    return {
      reservationId: id,
      alreadyCancelled: true,
      deleted: true,
    };
  }

  if (reservation.status !== 'confirmed' && reservation.status !== 'pending') {
    throw new Error('취소할 수 없는 예약 상태입니다.');
  }

  const startAt = reservation.start_at ?? reservation.start_time;
  if (!startAt) {
    throw new Error('예약 시작 시간이 없습니다.');
  }

  const { data: quoteRaw, error: quoteError } = await admin.rpc(
    'preview_cancel_refund_for_me',
    {
      p_reservation_id: id,
      p_user_id: userId,
    },
  );

  if (quoteError) {
    throw new Error(quoteError.message || '환불 금액 계산 실패');
  }

  const quote = parseQuote(quoteRaw);

  let tossCancel: unknown = null;
  if (reservation.payment_key && quote.refundAmount > 0) {
    tossCancel = await cancelTossPayment({
      paymentKey: reservation.payment_key,
      cancelReason: '고객 예약 취소',
      cancelAmount: quote.refundAmount,
    });
  }

  const { data: cancelData, error: rpcError } = await admin.rpc(
    'cancel_reservation_for_me',
    {
      p_reservation_id: id,
      p_user_id: userId,
      p_cancel_reason: 'customer',
      p_refund_amount: quote.refundAmount,
    },
  );

  if (rpcError) {
    throw new Error(rpcError.message || '예약 취소 저장 실패');
  }

  if (quote.restoreBenefits) {
    try {
      await admin.rpc('restore_booking_benefits_after_cancel', {
        p_user_id: userId,
        p_reservation_id: id,
        p_restore_benefits: true,
      });
    } catch (restoreErr) {
      console.error('benefit restore failed:', restoreErr);
    }
  }

  if (reservation.order_id) {
    const fullRefund =
      quote.refundAmount > 0 && quote.refundAmount >= quote.paidAmount;
    if (fullRefund) {
      await admin
        .from('payment_orders')
        .update(paymentOrderCancelledUpdate())
        .eq('order_id', reservation.order_id)
        .eq('user_id', userId);
    }
  }

  const vehicleRaw = reservation.vehicles as {
    model_name?: string;
    complex_id?: string;
  } | null;
  const vehicleName = vehicleRaw?.model_name?.trim() || '차량';

  try {
    await dispatchPushScenario({
      admin,
      scenario: 'customer_reservation_cancelled',
      payload: {
        userId,
        reservationId: id,
        vehicleName,
      },
    });
    const complexId = await resolveComplexId(admin, {
      reservationId: id,
      userId,
      vehicleName,
    });
    if (complexId) {
      await dispatchPushScenario({
        admin,
        scenario: 'staff_reservation_cancelled',
        payload: { complexId, reservationId: id, vehicleName },
      });
    }
  } catch (pushErr) {
    console.error('cancel push failed:', pushErr);
  }

  const cancelResult = (cancelData ?? {}) as Record<string, unknown>;

  return {
    reservationId: id,
    orderId: reservation.order_id,
    cancelled: true,
    refund: quote.refundAmount > 0,
    refundAmount: quote.refundAmount,
    refundRate: quote.refundRate,
    refundPercent: quote.refundPercent,
    paidAmount: quote.paidAmount,
    restoreBenefits: quote.restoreBenefits,
    toss: tossCancel,
    ...cancelResult,
  };
}
