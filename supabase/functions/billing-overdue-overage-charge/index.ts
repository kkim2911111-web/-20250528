import { handleCors, jsonResponse } from '../_shared/http.ts';
import { executeOverdueOverageCharge } from '../_shared/billing_charge_execute.ts';
import {
  enqueueBillingRetry,
  notifyBillingPaymentFailed,
} from '../_shared/billing_retry.ts';
import { getAdminClient } from '../_shared/payment.ts';

const MAX_BILLING_RETRIES = 3;

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  try {
    const admin = getAdminClient();
    const body = await req.json();
    const reservationId = body?.reservationId?.toString()?.trim();
    const userId = body?.userId?.toString()?.trim();
    const amount = Number(body?.amount ?? 0);
    const billedHours = Number(body?.billedHours ?? 0);
    let complexId = body?.complexId?.toString()?.trim() || null;

    if (!reservationId || !userId) {
      return jsonResponse({ error: 'reservationId 와 userId 가 필요합니다.' }, 400);
    }
    if (!Number.isInteger(amount) || amount <= 0) {
      return jsonResponse({ error: '청구 금액이 없습니다.' }, 400);
    }

    const extHours = Number.isInteger(billedHours) && billedHours > 0
      ? billedHours
      : null;

    try {
      const result = await executeOverdueOverageCharge(admin, {
        reservation_id: reservationId,
        user_id: userId,
        amount,
        extension_hours: extHours,
      });
      return jsonResponse({ ok: true, ...result });
    } catch (chargeErr) {
      const err = chargeErr as Error & { code?: string };
      console.error('[billing-overdue-overage-charge] charge', err);

      if (err.message.includes('이미 초과 이용 요금이 청구되었습니다')) {
        return jsonResponse({ ok: true, alreadyCharged: true });
      }

      if (!complexId) {
        try {
          const { data: resRow } = await admin
            .from('reservations')
            .select('vehicles(complex_id)')
            .eq('id', reservationId)
            .maybeSingle();
          const vehicles = resRow?.vehicles as { complex_id?: string } | null;
          complexId = vehicles?.complex_id?.toString() ?? null;
        } catch (_) {}
      }

      try {
        await enqueueBillingRetry(admin, {
          chargeType: 'overdue_overage',
          reservationId,
          userId,
          amount,
          complexId,
          extensionHours: extHours,
          lastError: err.message || '결제 실패',
        });
        await notifyBillingPaymentFailed(admin, {
          chargeType: 'overdue_overage',
          reservationId,
          userId,
          amount,
          complexId,
          retryCount: 0,
          maxRetries: MAX_BILLING_RETRIES,
          isFinal: false,
          isOverdueOverage: true,
        });
      } catch (retryErr) {
        console.error('[billing-overdue-overage-charge] retry enqueue', retryErr);
      }

      return jsonResponse(
        {
          error: err.message || '결제에 실패했습니다.',
          code: err.code ?? 'billing_charge_failed',
          enqueued: true,
        },
        402,
      );
    }
  } catch (e) {
    const err = e as Error;
    console.error('[billing-overdue-overage-charge]', err);
    return jsonResponse({ error: err.message || '초과 이용 요금 결제 실패' }, 500);
  }
});
