import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';

type ReservationRow = {
  id: string;
  user_id: string;
  vehicle_id: string;
  status: string;
  start_at?: string | null;
  start_time?: string | null;
  end_at?: string | null;
  end_time?: string | null;
  vehicles?: { model_name?: string; name?: string; complex_id?: string } | null;
};

function startAt(row: ReservationRow): string | null {
  return row.start_at ?? row.start_time ?? null;
}

function endAt(row: ReservationRow): string | null {
  return row.end_at ?? row.end_time ?? null;
}

function vehicleName(row: ReservationRow): string {
  const v = row.vehicles;
  return v?.model_name?.trim() || v?.name?.trim() || '차량';
}

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

async function hasNextReservation(
  admin: ReturnType<typeof getAdminClient>,
  vehicleId: string,
  afterIso: string,
): Promise<{ exists: boolean; nextStartAt?: string }> {
  const { data } = await admin
    .from('reservations')
    .select('id, start_at, start_time')
    .eq('vehicle_id', vehicleId)
    .in('status', ['confirmed', 'pending'])
    .gt('start_at', afterIso)
    .order('start_at', { ascending: true })
    .limit(1);

  if (data?.length) {
    const row = data[0] as ReservationRow;
    return { exists: true, nextStartAt: startAt(row) ?? undefined };
  }

  const { data: legacy } = await admin
    .from('reservations')
    .select('id, start_time')
    .eq('vehicle_id', vehicleId)
    .in('status', ['confirmed', 'pending'])
    .gt('start_time', afterIso)
    .order('start_time', { ascending: true })
    .limit(1);

  if (legacy?.length) {
    const row = legacy[0] as ReservationRow;
    return { exists: true, nextStartAt: startAt(row) ?? undefined };
  }

  return { exists: false };
}

/** pg_cron — 대여/반납 10분 전·지연·충돌 위험 알림 */
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

  const admin = getAdminClient();
  const now = Date.now();
  const in5 = new Date(now + 5 * 60 * 1000).toISOString();
  const in15 = new Date(now + 15 * 60 * 1000).toISOString();
  const in30 = new Date(now + 30 * 60 * 1000).toISOString();

  let dispatched = 0;

  try {
    const { data: startSoon } = await admin
      .from('reservations')
      .select('id, user_id, vehicle_id, status, start_at, start_time, vehicles(model_name, name, complex_id)')
      .eq('status', 'confirmed')
      .gte('start_at', in5)
      .lte('start_at', in15);

    for (const row of (startSoon ?? []) as ReservationRow[]) {
      const scenario = 'customer_rental_start_10min';
      if (await hasSent(admin, row.id, scenario)) continue;
      await dispatchPushScenario({
        admin,
        scenario,
        payload: {
          userId: row.user_id,
          reservationId: row.id,
          vehicleName: vehicleName(row),
          startAt: startAt(row) ?? '',
        },
      });
      await markSent(admin, row.id, scenario);
      dispatched++;
    }

    const { data: returnSoon } = await admin
      .from('reservations')
      .select('id, user_id, vehicle_id, status, end_at, end_time, vehicles(model_name, name, complex_id)')
      .eq('status', 'in_use')
      .gte('end_at', in5)
      .lte('end_at', in15);

    for (const row of (returnSoon ?? []) as ReservationRow[]) {
      const end = endAt(row) ?? '';
      const next = await hasNextReservation(admin, row.vehicle_id, end);
      const scenario = next.exists
        ? 'customer_return_10min_next_booking'
        : 'customer_return_10min';
      if (await hasSent(admin, row.id, scenario)) continue;
      await dispatchPushScenario({
        admin,
        scenario,
        payload: {
          userId: row.user_id,
          reservationId: row.id,
          vehicleName: vehicleName(row),
          endAt: end,
        },
      });
      await markSent(admin, row.id, scenario);
      dispatched++;
    }

    const { data: overdue } = await admin
      .from('reservations')
      .select('id, user_id, vehicle_id, status, end_at, end_time, vehicles(model_name, name, complex_id)')
      .eq('status', 'in_use')
      .lt('end_at', new Date(now).toISOString());

    for (const row of (overdue ?? []) as ReservationRow[]) {
      const scenario = 'customer_return_overdue';
      if (await hasSent(admin, row.id, scenario)) continue;
      await dispatchPushScenario({
        admin,
        scenario,
        payload: {
          userId: row.user_id,
          reservationId: row.id,
          vehicleName: vehicleName(row),
          endAt: endAt(row) ?? '',
        },
      });
      await markSent(admin, row.id, scenario);

      await dispatchPushScenario({
        admin,
        scenario: 'staff_return_overdue',
        payload: {
          reservationId: row.id,
          vehicleName: vehicleName(row),
          userId: row.user_id,
        },
      });
      await markSent(admin, row.id, 'staff_return_overdue');
      dispatched++;
    }

    const { data: conflictRisk } = await admin
      .from('reservations')
      .select('id, user_id, vehicle_id, status, end_at, end_time, vehicles(model_name, name, complex_id)')
      .eq('status', 'in_use')
      .gte('end_at', new Date(now).toISOString())
      .lte('end_at', in30);

    for (const row of (conflictRisk ?? []) as ReservationRow[]) {
      const end = endAt(row) ?? '';
      const next = await hasNextReservation(admin, row.vehicle_id, end);
      if (!next.exists) continue;
      const scenario = 'staff_conflict_risk';
      if (await hasSent(admin, row.id, scenario)) continue;
      await dispatchPushScenario({
        admin,
        scenario,
        payload: {
          reservationId: row.id,
          vehicleName: vehicleName(row),
          nextStartAt: next.nextStartAt ?? '',
        },
      });
      await markSent(admin, row.id, scenario);
      dispatched++;
    }

    return jsonResponse({ ok: true, dispatched });
  } catch (e) {
    const err = e as Error;
    console.error('scheduled-push-reminders failed:', err.message);
    return jsonResponse({ error: err.message }, 500);
  }
});
