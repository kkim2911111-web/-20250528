import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { makeOrderId } from './payment.ts';
import { cancelTossPayment, chargeTossBilling } from './toss.ts';
import { sendPushToUser } from './fcm.ts';

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

export async function executeDeductibleCharge(
  admin: SupabaseClient,
  reservationId: string,
): Promise<{ ok: true; paymentKey: string; orderId: string }> {
  const { data: reservation, error } = await admin
    .from('reservations')
    .select(
      'id, user_id, vehicle_id, status, is_accident, deductible_charged, deductible_waived, start_at, start_time, end_at, end_time, vehicles(complex_id, model_name)',
    )
    .eq('id', reservationId)
    .maybeSingle();

  if (error || !reservation) {
    throw new Error('예약을 찾을 수 없습니다.');
  }

  const row = reservation as ReservationRow;
  if (row.is_accident !== true) throw new Error('사고 예약만 면책금을 청구할 수 있습니다.');
  if (row.deductible_charged === true) throw new Error('이미 면책금이 청구되었습니다.');
  if (row.deductible_waived === true) throw new Error('면책금이 면제된 예약입니다.');

  const renterUserId = row.user_id?.toString();
  if (!renterUserId) throw new Error('임차인 정보가 없습니다.');

  const { data: renterProfile } = await admin
    .from('user_profiles')
    .select('toss_billing_key, payment_card_registered')
    .eq('user_id', renterUserId)
    .maybeSingle();

  const billingKey = renterProfile?.toss_billing_key?.toString()?.trim();
  if (!billingKey || renterProfile?.payment_card_registered !== true) {
    const err = new Error('고객에게 등록된 결제카드가 없습니다.') as Error & { code?: string };
    err.code = 'billing_key_missing';
    throw err;
  }

  const vehicleName = row.vehicles?.model_name?.toString()?.trim() || '단지카';
  const orderId = `ded_${reservationId}_${makeOrderId()}`;

  let paymentKey: string | null = null;
  try {
    const charge = await chargeTossBilling({
      billingKey,
      customerKey: renterUserId,
      amount: DEDUCTIBLE_AMOUNT,
      orderId,
      orderName: '면책금',
    });
    paymentKey = charge.paymentKey;
    if (!paymentKey) throw new Error('결제 승인 키를 받지 못했습니다.');

    const startTime = row.start_at ?? row.start_time ?? null;
    const endTime = row.end_at ?? row.end_time ?? null;

    const { error: orderErr } = await admin.from('payment_orders').insert({
      order_id: orderId,
      user_id: renterUserId,
      vehicle_id: String(row.vehicle_id),
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
      await cancelTossPayment({
        paymentKey,
        cancelReason: '결제 내역 저장 실패',
        cancelAmount: DEDUCTIBLE_AMOUNT,
      });
      throw new Error(orderErr.message);
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
      await cancelTossPayment({
        paymentKey,
        cancelReason: '면책금 상태 저장 실패',
        cancelAmount: DEDUCTIBLE_AMOUNT,
      });
      throw new Error(updateErr.message);
    }

    const pushTitle = '면책금 청구 안내';
    const pushBody = '면책금 ₩500,000이 청구되었습니다';
    try {
      await sendPushToUser({
        admin,
        userId: renterUserId,
        title: pushTitle,
        body: pushBody,
        data: { type: 'deductible_charged', reservation_id: reservationId },
      });
      await admin.from('notifications').insert({
        user_id: renterUserId,
        title: pushTitle,
        body: pushBody,
        type: 'deductible_charged',
        reservation_id: reservationId,
        is_read: false,
      });
    } catch (_) {}

    return { ok: true, paymentKey, orderId };
  } catch (e) {
    if (paymentKey) {
      try {
        await cancelTossPayment({
          paymentKey,
          cancelReason: '면책금 처리 오류',
          cancelAmount: DEDUCTIBLE_AMOUNT,
        });
      } catch (_) {}
    }
    throw e;
  }
}

export async function executeExtensionCharge(
  admin: SupabaseClient,
  params: {
    reservationId: string;
    userId: string;
    extensionHours: number;
  },
): Promise<{ ok: true; addedPrice: number; paymentKey?: string; orderId?: string }> {
  const { reservationId, userId, extensionHours } = params;

  const { data: checkRaw, error: checkErr } = await admin.rpc(
    'check_rental_extension_for_me',
    {
      p_reservation_id: reservationId,
      p_extension_hours: extensionHours,
      p_user_id: userId,
    },
  );

  if (checkErr) throw new Error(checkErr.message);
  const check = checkRaw as Record<string, unknown>;
  if (check?.eligible !== true) {
    throw new Error((check?.message as string) ?? '연장할 수 없습니다.');
  }

  const addedPrice = Number(check.addedPrice ?? 0);
  if (!Number.isInteger(addedPrice) || addedPrice < 0) {
    throw new Error('추가 요금 계산 오류');
  }

  if (addedPrice === 0) {
    const { error: applyErr } = await admin.rpc('apply_rental_extension_for_me', {
      p_reservation_id: reservationId,
      p_extension_hours: extensionHours,
      p_payment_key: null,
      p_payment_order_id: null,
      p_user_id: userId,
    });
    if (applyErr) throw new Error(applyErr.message);
    return { ok: true, addedPrice: 0 };
  }

  const { data: profile } = await admin
    .from('user_profiles')
    .select('toss_billing_key, payment_card_registered')
    .eq('user_id', userId)
    .maybeSingle();

  const billingKey = profile?.toss_billing_key?.toString()?.trim();
  if (!billingKey || profile?.payment_card_registered !== true) {
    const err = new Error('등록된 결제카드가 없습니다.') as Error & { code?: string };
    err.code = 'billing_key_missing';
    throw err;
  }

  const orderId = `ext_${reservationId}_${makeOrderId()}`;
  let paymentKey: string | null = null;

  try {
    const charge = await chargeTossBilling({
      billingKey,
      customerKey: userId,
      amount: addedPrice,
      orderId,
      orderName: `대여 연장 ${extensionHours}시간`,
    });
    paymentKey = charge.paymentKey;
    if (!paymentKey) throw new Error('결제 승인 키를 받지 못했습니다.');

    const { error: applyErr } = await admin.rpc('apply_rental_extension_for_me', {
      p_reservation_id: reservationId,
      p_extension_hours: extensionHours,
      p_payment_key: paymentKey,
      p_payment_order_id: orderId,
      p_user_id: userId,
    });

    if (applyErr) {
      await cancelTossPayment({
        paymentKey,
        cancelReason: '연장 적용 실패',
        cancelAmount: addedPrice,
      });
      throw new Error(applyErr.message);
    }

    return { ok: true, addedPrice, paymentKey, orderId };
  } catch (e) {
    if (paymentKey) {
      try {
        await cancelTossPayment({
          paymentKey,
          cancelReason: '연장 처리 오류',
          cancelAmount: addedPrice,
        });
      } catch (_) {}
    }
    throw e;
  }
}
