import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { hasNextConfirmedReservationWithinBuffer } from '../_shared/next_confirmed_reservation.ts';
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
  vehicles?: { model_name?: string; complex_id?: string } | null;
};

function startAt(row: ReservationRow): string | null {
  return row.start_at ?? row.start_time ?? null;
}

function endAt(row: ReservationRow): string | null {
  return row.end_at ?? row.end_time ?? null;
}

function vehicleName(row: ReservationRow): string {
  const v = row.vehicles;
  return v?.model_name?.trim() || '차량';
}

function parseMs(iso: string | null): number | null {
  if (!iso) return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
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

async function dispatchIfSent(
  admin: ReturnType<typeof getAdminClient>,
  scenario: Parameters<typeof dispatchPushScenario>[0]['scenario'],
  payload: Record<string, string>,
): Promise<boolean> {
  const result = await dispatchPushScenario({
    admin,
    scenario,
    payload,
  });
  if (result.skipped) return false;
  return (result.customerSent + result.staffSent) > 0;
}

async function hasNextReservation(
  admin: ReturnType<typeof getAdminClient>,
  vehicleId: string,
  endIso: string,
  excludeReservationId?: string,
): Promise<{ exists: boolean; nextStartAt?: string }> {
  return hasNextConfirmedReservationWithinBuffer(admin, {
    vehicleId,
    endAtIso: endIso,
    excludeReservationId,
  });
}

const RESERVATION_SELECT =
  'id, user_id, vehicle_id, status, start_at, start_time, end_at, end_time, vehicles(model_name, complex_id)';

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
  const windowStart = now + 5 * 60 * 1000;
  const windowEnd = now + 15 * 60 * 1000;
  const overdueCutoff = now;
  const conflictEnd = now + 30 * 60 * 1000;

  let dispatched = 0;

  try {
    const { data: confirmed } = await admin
      .from('reservations')
      .select(RESERVATION_SELECT)
      .eq('status', 'confirmed');

    for (const row of (confirmed ?? []) as ReservationRow[]) {
      const startMs = parseMs(startAt(row));
      if (startMs == null || startMs < windowStart || startMs > windowEnd) {
        continue;
      }

      const scenario = 'customer_rental_start_10min';
      if (await hasSent(admin, row.id, scenario)) continue;

      const sent = await dispatchIfSent(admin, scenario, {
        userId: row.user_id,
        reservationId: row.id,
        vehicleName: vehicleName(row),
        startAt: startAt(row) ?? '',
      });
      if (sent) {
        await markSent(admin, row.id, scenario);
        dispatched++;
      }
    }

    const { data: inUse } = await admin
      .from('reservations')
      .select(RESERVATION_SELECT)
      .eq('status', 'in_use');

    for (const row of (inUse ?? []) as ReservationRow[]) {
      const end = endAt(row) ?? '';
      const endMs = parseMs(end);
      if (endMs == null) continue;

      if (endMs >= windowStart && endMs <= windowEnd) {
        const next = await hasNextReservation(
          admin,
          row.vehicle_id,
          end,
          row.id,
        );
        const scenario = next.exists
          ? 'customer_return_imminent_with_next'
          : 'customer_return_imminent_no_next';
        if (await hasSent(admin, row.id, scenario)) continue;

        const sent = await dispatchIfSent(admin, scenario, {
          userId: row.user_id,
          reservationId: row.id,
          vehicleName: vehicleName(row),
          endAt: end,
        });
        if (sent) {
          await markSent(admin, row.id, scenario);
          dispatched++;
        }
      }

      if (endMs >= overdueCutoff && endMs <= conflictEnd) {
        const next = await hasNextReservation(
          admin,
          row.vehicle_id,
          end,
          row.id,
        );
        if (!next.exists) continue;
        const scenario = 'staff_conflict_risk';
        if (await hasSent(admin, row.id, scenario)) continue;

        const sent = await dispatchIfSent(admin, scenario, {
          reservationId: row.id,
          vehicleName: vehicleName(row),
          nextStartAt: next.nextStartAt ?? '',
        });
        if (sent) {
          await markSent(admin, row.id, scenario);
          dispatched++;
        }
      }
    }

    return jsonResponse({ ok: true, dispatched });
  } catch (e) {
    const err = e as Error;
    console.error('scheduled-push-reminders failed:', err.message);
    return jsonResponse({ error: err.message }, 500);
  }
});
