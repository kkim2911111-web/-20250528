import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';
import { cancelReservationForUser } from '../_shared/reservation_cancel.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const user = await getUserFromRequest(req);
    if (!user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const { reservationId } = await req.json();
    if (!reservationId) {
      return jsonResponse({ error: 'reservationId 가 필요합니다.' }, 400);
    }

    const admin = getAdminClient();
    const result = await cancelReservationForUser({
      admin,
      userId: user.id,
      reservationId,
    });

    return jsonResponse({
      ok: true,
      cancelled: true,
      ...result,
    });
  } catch (e) {
    const err = e as Error & { code?: string };
    return jsonResponse(
      { error: err.message || '예약 취소 실패', code: err.code },
      500,
    );
  }
});
