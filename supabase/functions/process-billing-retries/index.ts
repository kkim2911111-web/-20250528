import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import {
  executeDeductibleCharge,
  executeExtensionCharge,
  executeOverdueOverageCharge,
} from '../_shared/billing_charge_execute.ts';
import {
  markRetryFailed,
  markRetrySucceeded,
  type BillingChargeType,
} from '../_shared/billing_retry.ts';

type RetryRow = {
  id: string;
  charge_type: BillingChargeType;
  reservation_id: string;
  user_id: string;
  complex_id?: string | null;
  amount: number;
  extension_hours?: number | null;
  retry_count: number;
  max_retries: number;
};

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const admin = getAdminClient();
    const now = new Date().toISOString();

    const { data: rows, error } = await admin
      .from('billing_charge_retries')
      .select(
        'id, charge_type, reservation_id, user_id, complex_id, amount, extension_hours, retry_count, max_retries',
      )
      .eq('status', 'pending')
      .lte('next_retry_at', now)
      .order('next_retry_at', { ascending: true })
      .limit(50);

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    const results: Record<string, string> = {};

    for (const raw of rows ?? []) {
      const row = raw as RetryRow;
      try {
        if (row.charge_type === 'deductible') {
          await executeDeductibleCharge(admin, row.reservation_id);
        } else if (row.charge_type === 'overdue_overage') {
          await executeOverdueOverageCharge(admin, row);
        } else {
          const hours = row.extension_hours ?? 1;
          await executeExtensionCharge(admin, {
            reservationId: row.reservation_id,
            userId: row.user_id,
            extensionHours: hours,
          });
        }
        await markRetrySucceeded(admin, row.id);
        results[row.id] = 'succeeded';
      } catch (e) {
        const err = e as Error;
        const status = await markRetryFailed(admin, row.id, {
          lastError: err.message || '결제 실패',
          retryCount: row.retry_count,
          maxRetries: row.max_retries,
          chargeType: row.charge_type,
          reservationId: row.reservation_id,
          userId: row.user_id,
          amount: row.amount,
          complexId: row.complex_id,
          extensionHours: row.extension_hours,
          isOverdueOverage: row.charge_type === 'overdue_overage',
        });
        results[row.id] = status;
      }
    }

    return jsonResponse({
      ok: true,
      processed: Object.keys(results).length,
      results,
    });
  } catch (e) {
    const err = e as Error;
    console.error('[process-billing-retries]', err);
    return jsonResponse({ error: err.message }, 500);
  }
});
