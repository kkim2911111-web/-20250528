import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario } from './push_scenarios.ts';
import { cancelTossPayment } from './toss.ts';
import { paymentOrderCancelledUpdate } from './payment_order_status.ts';

export async function forceCancelReservationWithRefund(params: {
  admin: SupabaseClient;
  userId: string;
  reservationId: string;
  cancelReason?: string;
  notifyCustomer?: boolean;
}): Promise<{
  reservationId: string;
  cancelled: boolean;
  refunded: boolean;
  alreadyGone?: boolean;
}> {
  const { admin, userId, reservationId } = params;
  const id = reservationId?.trim();
  if (!id) {
    throw new Error('예약 ID가 없습니다.');
  }

  const { data: reservation, error: reservationError } = await admin
    .from('reservations')
    .select(
      'id, status, payment_key, total_price, order_id, vehicle_id, vehicles(model_name, complex_id)',
    )
    .eq('id', id)
    .eq('user_id', userId)
    .maybeSingle();

  if (reservationError) {
    throw new Error(reservationError.message || '예약 조회 실패');
  }

  if (!reservation) {
    return { reservationId: id, cancelled: true, refunded: false, alreadyGone: true };
  }

  if (reservation.status !== 'confirmed' && reservation.status !== 'pending') {
    return { reservationId: id, cancelled: false, refunded: false };
  }

  let refunded = false;
  if (reservation.payment_key) {
    try {
      await cancelTossPayment({
        paymentKey: reservation.payment_key,
        cancelReason: params.cancelReason ?? '관리자 취소',
        cancelAmount: Number(reservation.total_price),
      });
      refunded = true;
    } catch (e) {
      console.error('[forceCancel] toss refund failed:', e);
    }
  }

  const { error: rpcError } = await admin.rpc('cancel_reservation_for_me', {
    p_reservation_id: id,
    p_user_id: userId,
    p_cancel_reason: 'blacklist_auto',
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

  try {
    await admin.rpc('restore_user_coupon', { p_reservation_id: id });
  } catch (_) {}

  try {
    await admin.rpc('restore_used_points', { p_reservation_id: id });
  } catch (_) {}

  const vehicleRaw = reservation.vehicles as {
    model_name?: string;
    complex_id?: string;
  } | null;
  const vehicleName = vehicleRaw?.model_name?.trim() || '차량';
  const complexId = vehicleRaw?.complex_id?.toString();

  if (params.notifyCustomer !== false) {
    try {
      await dispatchPushScenario({
        admin,
        scenario: 'customer_reservation_cancelled',
        payload: {
          userId,
          reservationId: id,
          vehicleName,
          reason: params.cancelReason ?? '서비스 이용 제한',
        },
      });
      if (complexId) {
        await dispatchPushScenario({
          admin,
          scenario: 'staff_reservation_cancelled',
          payload: { complexId, reservationId: id, vehicleName },
        });
      }
    } catch (pushErr) {
      console.error('[forceCancel] push failed:', pushErr);
    }
  }

  return { reservationId: id, cancelled: true, refunded };
}
