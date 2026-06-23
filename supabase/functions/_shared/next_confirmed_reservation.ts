import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const BUFFER_MS = 30 * 60 * 1000;

function parseMs(iso: string | null | undefined): number | null {
  if (!iso) return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
}

function startAt(row: {
  start_at?: string | null;
  start_time?: string | null;
}): string | null {
  return row.start_at ?? row.start_time ?? null;
}

/**
 * 반납 임박·지연 푸시 — 다음 예약자( confirmed, end 직후 30분 버퍼 이내 ) 존재 여부
 */
export async function hasNextConfirmedReservationWithinBuffer(
  admin: SupabaseClient,
  params: {
    vehicleId: string;
    endAtIso: string;
    excludeReservationId?: string;
  },
): Promise<{ exists: boolean; nextStartAt?: string }> {
  const endMs = parseMs(params.endAtIso);
  if (endMs == null || !params.vehicleId) return { exists: false };

  const bufferEndMs = endMs + BUFFER_MS;

  const { data, error } = await admin
    .from('reservations')
    .select('id, start_at, start_time, status')
    .eq('vehicle_id', params.vehicleId)
    .eq('status', 'confirmed');

  if (error) {
    console.error('[next_confirmed_reservation] fetch failed:', error.message);
    return { exists: false };
  }

  let best: { start: string; ms: number } | null = null;

  for (const row of data ?? []) {
    if (
      params.excludeReservationId &&
      row.id?.toString() === params.excludeReservationId
    ) {
      continue;
    }

    const start = startAt(row);
    const startMs = parseMs(start);
    if (startMs == null) continue;
    if (startMs <= endMs) continue;
    if (startMs > bufferEndMs) continue;

    if (!best || startMs < best.ms) {
      best = { start: start!, ms: startMs };
    }
  }

  if (!best) return { exists: false };
  return { exists: true, nextStartAt: best.start };
}
