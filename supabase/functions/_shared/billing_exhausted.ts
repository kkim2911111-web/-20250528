import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario } from './push_scenarios.ts';
import { sendPushToUser } from './fcm.ts';
import type { BillingChargeType } from './billing_retry.ts';

export async function handleBillingExhausted(
  admin: SupabaseClient,
  params: {
    chargeType: BillingChargeType;
    reservationId: string;
    userId: string;
    amount: number;
    complexId?: string | null;
    extensionHours?: number | null;
    isOverdueOverage?: boolean;
  },
): Promise<void> {
  const { chargeType, reservationId, userId, amount } = params;
  const amountStr = `₩${amount.toLocaleString('ko-KR')}`;

  let vehicleName = '차량';
  let complexId = params.complexId?.toString() ?? null;

  try {
    const { data: resRow } = await admin
      .from('reservations')
      .select('vehicles(model_name, complex_id)')
      .eq('id', reservationId)
      .maybeSingle();
    const vehicles = resRow?.vehicles as {
      model_name?: string;
      complex_id?: string;
    } | null;
    vehicleName = vehicles?.model_name?.toString()?.trim() || vehicleName;
    complexId = complexId ?? vehicles?.complex_id?.toString() ?? null;
  } catch (e) {
    console.error('[billing_exhausted] reservation lookup', e);
  }

  if (chargeType === 'deductible') {
    try {
      await admin.rpc('mark_deductible_unpaid_for_service', {
        p_reservation_id: reservationId,
        p_amount: amount,
      });
    } catch (e) {
      console.error('[billing_exhausted] mark unpaid', e);
    }

    if (complexId) {
      try {
        await dispatchPushScenario({
          admin,
          scenario: 'staff_deductible_payment_exhausted',
          payload: {
            complexId,
            reservationId,
            vehicleName,
            reservationNumber: reservationId,
            reason: `미수 ${amountStr} — 수동 결제 처리가 필요합니다.`,
          },
        });
      } catch (e) {
        console.error('[billing_exhausted] staff deductible notify', e);
      }
    }
    return;
  }

  const extensionHours = params.extensionHours ?? 1;
  if (chargeType === 'overdue_overage') {
    const customerTitle = '초과 이용 요금 결제 실패';
    const customerBody =
      '초과 이용 요금 자동결제에 실패했습니다. 카드 등록 상태를 확인해주세요.';

    try {
      await sendPushToUser({
        admin,
        userId,
        title: customerTitle,
        body: customerBody,
        data: {
          type: 'billing_payment_failed',
          reservation_id: reservationId,
          charge_type: 'overdue_overage',
        },
      });
      await admin.from('notifications').insert({
        user_id: userId,
        title: customerTitle,
        body: customerBody,
        type: 'billing_payment_failed',
        reservation_id: reservationId,
        is_read: false,
      });
    } catch (e) {
      console.error('[billing_exhausted] customer overdue notify', e);
    }

    if (complexId) {
      try {
        await dispatchPushScenario({
          admin,
          scenario: 'staff_billing_payment_failed',
          payload: {
            complexId,
            reservationId,
            vehicleName,
            reason: `초과 이용 요금 ${amountStr} — 수동 결제 처리가 필요합니다.`,
          },
        });
      } catch (e) {
        console.error('[billing_exhausted] staff overdue notify', e);
      }
    }
    return;
  }

  try {
    await admin.rpc('cancel_extension_charge_exhausted_for_service', {
      p_reservation_id: reservationId,
      p_extension_hours: extensionHours,
    });
  } catch (e) {
    console.error('[billing_exhausted] cancel extension', e);
  }

  const customerTitle = '연장 취소 안내';
  const customerBody =
    '연장 결제에 실패하여 연장이 취소되었습니다. 카드 등록 상태를 확인해주세요.';

  try {
    await sendPushToUser({
      admin,
      userId,
      title: customerTitle,
      body: customerBody,
      data: {
        type: 'extension_charge_cancelled',
        reservation_id: reservationId,
      },
    });
    await admin.from('notifications').insert({
      user_id: userId,
      title: customerTitle,
      body: customerBody,
      type: 'extension_charge_cancelled',
      reservation_id: reservationId,
      is_read: false,
    });
  } catch (e) {
    console.error('[billing_exhausted] customer extension notify', e);
  }

  if (complexId) {
    try {
      await dispatchPushScenario({
        admin,
        scenario: 'staff_extension_payment_exhausted',
        payload: {
          complexId,
          reservationId,
          vehicleName,
          reservationNumber: reservationId,
          reason: `${extensionHours}시간 연장 · ${amountStr}`,
        },
      });
    } catch (e) {
      console.error('[billing_exhausted] staff extension notify', e);
    }
  }
}
