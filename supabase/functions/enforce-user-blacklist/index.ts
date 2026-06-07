import { handleCors, jsonResponse } from '../_shared/http.ts';
import {
  getAdminClient,
  getUserClient,
  getUserFromRequest,
} from '../_shared/payment.ts';
import { forceCancelReservationWithRefund } from '../_shared/admin_reservation_cancel.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const caller = await getUserFromRequest(req);
    if (!caller) return jsonResponse({ error: 'Unauthorized' }, 401);

    const admin = getAdminClient();
    const userClient = getUserClient(authHeader);

    const { data: callerProfile } = await admin
      .from('user_profiles')
      .select('is_super_admin')
      .eq('user_id', caller.id)
      .maybeSingle();

    if (callerProfile?.is_super_admin !== true) {
      return jsonResponse({ error: '최고관리자 권한이 필요합니다.' }, 403);
    }

    const body = await req.json();
    const userId = body?.userId?.toString()?.trim();
    const blacklisted = body?.blacklisted === true;

    if (!userId) {
      return jsonResponse({ error: 'userId 가 필요합니다.' }, 400);
    }

    const { error: blacklistErr } = await userClient.rpc(
      'set_super_admin_user_blacklist',
      {
        p_user_id: userId,
        p_blacklisted: blacklisted,
      },
    );
    if (blacklistErr) {
      throw new Error(blacklistErr.message);
    }

    const cancelled: Array<{ reservationId: string; refunded: boolean }> = [];

    if (blacklisted) {
      const { data: reservations, error: listErr } = await admin.rpc(
        'list_confirmed_reservations_for_user',
        { p_user_id: userId },
      );

      if (listErr) {
        console.error('[enforce-user-blacklist] list', listErr);
      } else {
        for (const row of reservations ?? []) {
          const r = row as {
            reservation_id: string;
            vehicle_name?: string;
            complex_id?: string;
          };
          try {
            const result = await forceCancelReservationWithRefund({
              admin,
              userId,
              reservationId: r.reservation_id,
              cancelReason: '블랙리스트 등록에 따른 예약 취소',
              notifyCustomer: true,
            });
            if (result.cancelled) {
              cancelled.push({
                reservationId: result.reservationId,
                refunded: result.refunded,
              });
            }
          } catch (e) {
            console.error('[enforce-user-blacklist] cancel', r.reservation_id, e);
          }
        }
      }

      try {
        await dispatchPushScenario({
          admin,
          scenario: 'customer_blacklist_registered',
          payload: { userId },
        });
      } catch (e) {
        console.error('[enforce-user-blacklist] notify', e);
      }
    }

    return jsonResponse({
      ok: true,
      userId,
      blacklisted,
      cancelledCount: cancelled.length,
      cancelled,
    });
  } catch (e) {
    const err = e as Error;
    console.error('[enforce-user-blacklist]', err);
    return jsonResponse({ error: err.message }, 500);
  }
});
