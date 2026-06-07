import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';

type NoShowRow = {
  reservationId: string;
  userId: string;
  vehicleId: string;
};

async function hasSent(
  admin: ReturnType<typeof getAdminClient>,
  reservationId: string,
  scenario: string,
): Promise<boolean> {
  const { data } = await admin
    .from('push_reminder_log')
    .select('id')
    .eq('reservation_id', reservationId)
    .eq('scenario', scenario)
    .maybeSingle();
  return !!data;
}

async function markSent(
  admin: ReturnType<typeof getAdminClient>,
  reservationId: string,
  scenario: string,
) {
  await admin.from('push_reminder_log').insert({
    reservation_id: reservationId,
    scenario,
  });
}

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

    const { data: result, error } = await admin.rpc(
      'auto_return_expired_reservations',
    );

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    const payload = (result ?? {}) as Record<string, unknown>;
    const noShows = (payload.noShows ?? []) as NoShowRow[];
    let notified = 0;

    for (const row of noShows) {
      const reservationId = row.reservationId?.toString()?.trim();
      const userId = row.userId?.toString()?.trim();
      const vehicleId = row.vehicleId?.toString()?.trim();
      if (!reservationId || !userId) continue;

      const scenario = 'no_show_auto_completed';
      if (await hasSent(admin, reservationId, scenario)) continue;

      let complexId: string | null = null;
      let vehicleName = '차량';
      if (vehicleId) {
        const { data: vehicle } = await admin
          .from('vehicles')
          .select('model_name, complex_id')
          .eq('id', vehicleId)
          .maybeSingle();
        complexId = vehicle?.complex_id?.toString() ?? null;
        vehicleName = vehicle?.model_name?.toString()?.trim() || vehicleName;
      }

      try {
        await dispatchPushScenario({
          admin,
          scenario: 'customer_no_show_auto_completed',
          payload: {
            userId,
            reservationId,
            vehicleName,
          },
        });

        if (complexId) {
          await dispatchPushScenario({
            admin,
            scenario: 'staff_no_show_auto_completed',
            payload: {
              complexId,
              reservationId,
              vehicleName,
              reservationNumber: reservationId,
            },
          });
        }

        await markSent(admin, reservationId, scenario);
        notified++;
      } catch (e) {
        console.error('[scheduled-auto-return] notify', reservationId, e);
      }
    }

    return jsonResponse({
      ok: true,
      result: payload,
      notified,
    });
  } catch (e) {
    const err = e as Error;
    console.error('[scheduled-auto-return]', err);
    return jsonResponse({ error: err.message }, 500);
  }
});
