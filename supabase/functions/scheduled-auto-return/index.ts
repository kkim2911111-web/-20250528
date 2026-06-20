import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';

type ProcessedRow = {
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

async function fetchVehicleContext(
  admin: ReturnType<typeof getAdminClient>,
  vehicleId: string | null | undefined,
) {
  if (!vehicleId) {
    return { complexId: null as string | null, vehicleName: '차량' };
  }

  const { data: vehicle } = await admin
    .from('vehicles')
    .select('model_name, complex_id')
    .eq('id', vehicleId)
    .maybeSingle();

  return {
    complexId: vehicle?.complex_id?.toString() ?? null,
    vehicleName: vehicle?.model_name?.toString()?.trim() || '차량',
  };
}

async function fetchRenterName(
  admin: ReturnType<typeof getAdminClient>,
  userId: string,
): Promise<string> {
  const { data: profile } = await admin
    .from('user_profiles')
    .select('full_name')
    .eq('user_id', userId)
    .maybeSingle();

  const name = profile?.full_name?.toString()?.trim();
  return name && name.length > 0 ? name : '임차인';
}

async function notifyNoShows(
  admin: ReturnType<typeof getAdminClient>,
  rows: ProcessedRow[],
): Promise<number> {
  let notified = 0;

  for (const row of rows) {
    const reservationId = row.reservationId?.toString()?.trim();
    const userId = row.userId?.toString()?.trim();
    const vehicleId = row.vehicleId?.toString()?.trim();
    if (!reservationId || !userId) continue;

    const scenario = 'no_show_auto_completed';
    if (await hasSent(admin, reservationId, scenario)) continue;

    const { complexId, vehicleName } = await fetchVehicleContext(admin, vehicleId);
    const renterName = await fetchRenterName(admin, userId);

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
            renterName,
          },
        });
      }

      await markSent(admin, reservationId, scenario);
      notified++;
    } catch (e) {
      console.error('[scheduled-auto-return] no-show notify', reservationId, e);
    }
  }

  return notified;
}

async function notifyOverdues(
  admin: ReturnType<typeof getAdminClient>,
  rows: ProcessedRow[],
): Promise<number> {
  let notified = 0;

  for (const row of rows) {
    const reservationId = row.reservationId?.toString()?.trim();
    const userId = row.userId?.toString()?.trim();
    const vehicleId = row.vehicleId?.toString()?.trim();
    if (!reservationId || !userId) continue;

    const { data: resRow } = await admin
      .from('reservations')
      .select('overdue_notified_at')
      .eq('id', reservationId)
      .maybeSingle();

    if (resRow?.overdue_notified_at) continue;

    const { complexId, vehicleName } = await fetchVehicleContext(admin, vehicleId);
    const renterName = await fetchRenterName(admin, userId);
    const endAt = await admin
      .from('reservations')
      .select('end_at, end_time')
      .eq('id', reservationId)
      .maybeSingle();
    const scheduledEnd =
      endAt.data?.end_at?.toString() ?? endAt.data?.end_time?.toString() ?? '';

    try {
      await dispatchPushScenario({
        admin,
        scenario: 'customer_return_overdue',
        payload: {
          userId,
          reservationId,
          vehicleName,
          endAt: scheduledEnd,
        },
      });

      if (complexId) {
        await dispatchPushScenario({
          admin,
          scenario: 'staff_return_overdue',
          payload: {
            complexId,
            reservationId,
            vehicleName,
            renterName,
          },
        });
      }

      await admin.rpc('mark_overdue_notified_for_service', {
        p_reservation_id: reservationId,
      });
      notified++;
    } catch (e) {
      console.error('[scheduled-auto-return] overdue notify', reservationId, e);
    }
  }

  return notified;
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
    const noShows = (payload.noShows ?? []) as ProcessedRow[];
    const overdues = (payload.overdues ?? []) as ProcessedRow[];

    const noShowNotified = await notifyNoShows(admin, noShows);
    const overdueNotified = await notifyOverdues(admin, overdues);

    return jsonResponse({
      ok: true,
      result: payload,
      noShowNotified,
      overdueNotified,
    });
  } catch (e) {
    const err = e as Error;
    console.error('[scheduled-auto-return]', err);
    return jsonResponse({ error: err.message }, 500);
  }
});
