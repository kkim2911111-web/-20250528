import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario } from './push_scenarios.ts';
import { sendPushToUser } from './fcm.ts';
import { handleBillingExhausted } from './billing_exhausted.ts';

export type BillingChargeType = 'deductible' | 'extension';

const RETRY_INTERVAL_MS = 60 * 60 * 1000;
const MAX_RETRIES = 3;

export async function enqueueBillingRetry(
  admin: SupabaseClient,
  params: {
    chargeType: BillingChargeType;
    reservationId: string;
    userId: string;
    amount: number;
    complexId?: string | null;
    extensionHours?: number | null;
    lastError?: string;
  },
): Promise<void> {
  const extHours = params.extensionHours ?? null;
  const nextRetryAt = new Date(Date.now() + RETRY_INTERVAL_MS).toISOString();

  const { data: existing } = await admin
    .from('billing_charge_retries')
    .select('id')
    .eq('charge_type', params.chargeType)
    .eq('reservation_id', params.reservationId)
    .eq('status', 'pending')
    .maybeSingle();

  if (existing?.id) {
    await admin
      .from('billing_charge_retries')
      .update({
        last_error: params.lastError ?? null,
        next_retry_at: nextRetryAt,
        updated_at: new Date().toISOString(),
      })
      .eq('id', existing.id);
    return;
  }

  await admin.from('billing_charge_retries').insert({
    charge_type: params.chargeType,
    reservation_id: params.reservationId,
    user_id: params.userId,
    complex_id: params.complexId ?? null,
    amount: params.amount,
    extension_hours: extHours,
    retry_count: 0,
    max_retries: MAX_RETRIES,
    next_retry_at: nextRetryAt,
    last_error: params.lastError ?? null,
    status: 'pending',
  });
}

export async function notifyBillingPaymentFailed(
  admin: SupabaseClient,
  params: {
    chargeType: BillingChargeType;
    reservationId: string;
    userId: string;
    amount: number;
    complexId?: string | null;
    retryCount: number;
    maxRetries: number;
    isFinal: boolean;
    isOverdueOverage?: boolean;
  },
): Promise<void> {
  const label = params.chargeType === 'deductible'
    ? '면책금'
    : params.chargeType === 'extension' && params.isOverdueOverage
    ? '초과 이용 요금'
    : '연장 요금';
  const amountStr = `₩${params.amount.toLocaleString('ko-KR')}`;
  const retryNote = params.isFinal
    ? '자동 재시도가 모두 실패했습니다. 카드 등록 상태를 확인해주세요.'
    : `1시간 후 자동 재시도합니다 (${params.retryCount}/${params.maxRetries}).`;

  const customerTitle = `${label} 결제 실패`;
  const customerBody = `${amountStr} 결제에 실패했습니다. ${retryNote}`;

  try {
    await sendPushToUser({
      admin,
      userId: params.userId,
      title: customerTitle,
      body: customerBody,
      data: {
        type: 'billing_payment_failed',
        reservation_id: params.reservationId,
        charge_type: params.chargeType,
      },
    });
    await admin.from('notifications').insert({
      user_id: params.userId,
      title: customerTitle,
      body: customerBody,
      type: 'billing_payment_failed',
      reservation_id: params.reservationId,
      is_read: false,
    });
  } catch (e) {
    console.error('[billing_retry] customer notify', e);
  }

  if (params.complexId) {
    try {
      await dispatchPushScenario({
        admin,
        scenario: 'staff_billing_payment_failed',
        payload: {
          complexId: params.complexId,
          reservationId: params.reservationId,
          vehicleName: label,
          reason: `${amountStr} · ${retryNote}`,
        },
      });
    } catch (e) {
      console.error('[billing_retry] staff notify', e);
    }
  }
}

export async function markRetrySucceeded(
  admin: SupabaseClient,
  retryId: string,
): Promise<void> {
  await admin
    .from('billing_charge_retries')
    .update({
      status: 'succeeded',
      updated_at: new Date().toISOString(),
    })
    .eq('id', retryId);
}

export async function markRetryFailed(
  admin: SupabaseClient,
  retryId: string,
  params: {
    lastError: string;
    retryCount: number;
    maxRetries: number;
    chargeType: BillingChargeType;
    reservationId: string;
    userId: string;
    amount: number;
    complexId?: string | null;
    extensionHours?: number | null;
    isOverdueOverage?: boolean;
  },
): Promise<'pending' | 'exhausted'> {
  const nextCount = params.retryCount + 1;
  const exhausted = nextCount >= params.maxRetries;

  if (exhausted) {
    await admin
      .from('billing_charge_retries')
      .update({
        retry_count: nextCount,
        status: 'exhausted',
        last_error: params.lastError,
        updated_at: new Date().toISOString(),
      })
      .eq('id', retryId);

    await notifyBillingPaymentFailed(admin, {
      ...params,
      retryCount: nextCount,
      isFinal: true,
    });

    try {
      await handleBillingExhausted(admin, {
        chargeType: params.chargeType,
        reservationId: params.reservationId,
        userId: params.userId,
        amount: params.amount,
        complexId: params.complexId,
        extensionHours: params.extensionHours,
        isOverdueOverage: params.isOverdueOverage,
      });
    } catch (e) {
      console.error('[billing_retry] exhausted handling', e);
    }

    return 'exhausted';
  }

  const nextRetryAt = new Date(Date.now() + RETRY_INTERVAL_MS).toISOString();
  await admin
    .from('billing_charge_retries')
    .update({
      retry_count: nextCount,
      next_retry_at: nextRetryAt,
      last_error: params.lastError,
      updated_at: new Date().toISOString(),
    })
    .eq('id', retryId);

  await notifyBillingPaymentFailed(admin, {
    ...params,
    retryCount: nextCount,
    isFinal: false,
  });
  return 'pending';
}
