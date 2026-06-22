import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { processVehicleNotReturnedRefund } from '../_shared/vehicle_not_returned_refund.ts';

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
    const body = await req.json();
    const reservationId = body?.reservationId?.toString()?.trim();

    if (!reservationId) {
      return jsonResponse({ error: 'reservationId 가 필요합니다.' }, 400);
    }

    const admin = getAdminClient();
    const result = await processVehicleNotReturnedRefund(admin, reservationId);

    if (!result.ok) {
      return jsonResponse(
        { error: result.error || '환불 처리 실패' },
        result.error?.includes('아닙니다') ? 400 : 402,
      );
    }

    return jsonResponse({ ok: true, ...result });
  } catch (e) {
    const err = e as Error;
    console.error('[reservation-vehicle-not-returned-refund]', err);
    return jsonResponse({ error: err.message || '환불 처리 실패' }, 500);
  }
});
