import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario, resolveComplexId } from './push_scenarios.ts';
import { cancelTossPayment } from './toss.ts';
import { paymentOrderCancelledUpdate } from './payment_order_status.ts';

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
      'id, status, start_at, start_time, payment_key, payment_status, total_price, order_id, vehicle_id, vehicles(model_name, complex_id)',
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

  const startMs = new Date(startAt).getTime();
  const cutoffMs = Date.now() + 60 * 60 * 1000;
  if (startMs <= cutoffMs) {
    throw new Error('대여예약 1시간(60분)이전에는 예약취소가 불가능합니다');
  }

  let tossCancel: unknown = null;
  if (reservation.payment_key) {
    tossCancel = await cancelTossPayment({
      paymentKey: reservation.payment_key,
      cancelReason: '고객 예약 취소',
      cancelAmount: Number(reservation.total_price),
    });
  }

  const { error: rpcError } = await admin.rpc('cancel_reservation_for_me', {
    p_reservation_id: id,
    p_user_id: userId,
  });

  if (rpcError) {
    const { error: deleteError } = await admin
      .from('reservations')
      .delete()
      .eq('id', id)
      .eq('user_id', userId);

    if (deleteError) {
      throw new Error(rpcError.message || deleteError.message || '예약 취소 저장 실패');
    }
  }

  if (reservation.order_id) {
    await admin
      .from('payment_orders')
      .update(paymentOrderCancelledUpdate())
      .eq('order_id', reservation.order_id)
      .eq('user_id', userId);
  }

  const vehicleRaw = reservation.vehicles as {
    model_name?: string;
    complex_id?: string;
  } | null;
  const vehicleName =
    vehicleRaw?.model_name?.trim() || '차량';

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

  return {
    reservationId: id,
    orderId: reservation.order_id,
    deleted: true,
    refund: tossCancel != null,
    toss: tossCancel,
  };
}
