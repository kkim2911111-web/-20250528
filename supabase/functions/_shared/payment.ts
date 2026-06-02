import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export function getAdminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function getUserClient(authHeader: string): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  return createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function getUserFromRequest(req: Request) {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;

  const client = getUserClient(authHeader);

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

export function makeOrderId(): string {
  return `danji_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

export async function hasOverlap(
  admin: SupabaseClient,
  vehicleId: string,
  startTime: string,
  endTime: string,
): Promise<boolean> {
  const pairs: [string, string][] = [
    ['start_time', 'end_time'],
    ['start_at', 'end_at'],
  ];

  for (const [startCol, endCol] of pairs) {
    const { data, error } = await admin
      .from('reservations')
      .select('id')
      .eq('vehicle_id', String(vehicleId))
      .in('status', ['pending', 'confirmed'])
      .lt(startCol, endTime)
      .gt(endCol, startTime)
      .limit(1);

    if (!error && data?.length) return true;
    if (error && !error.message?.includes('column')) continue;
  }
  return false;
}

export async function createReservation(
  admin: SupabaseClient,
  order: Record<string, unknown>,
): Promise<string> {
  const base = {
    user_id: order.user_id,
    vehicle_id: String(order.vehicle_id),
    total_price: order.total_price,
    status: 'confirmed',
    payment_key: order.payment_key,
    order_id: order.order_id,
    payment_status: 'paid',
  };

  const variants = [
    { ...base, start_time: order.start_time, end_time: order.end_time },
    { ...base, start_at: order.start_time, end_at: order.end_time },
    {
      user_id: base.user_id,
      vehicle_id: base.vehicle_id,
      start_time: order.start_time,
      end_time: order.end_time,
      total_price: base.total_price,
      status: 'confirmed',
    },
  ];

  let lastError: { message?: string; code?: string } | null = null;
  for (const payload of variants) {
    const { data, error } = await admin
      .from('reservations')
      .insert(payload)
      .select('id')
      .single();
    if (!error && data?.id) return data.id as string;
    lastError = error;
    if (error?.code !== 'PGRST204' && !error?.message?.includes('column')) {
      break;
    }
  }
  throw new Error(lastError?.message ?? 'reservations insert failed');
}
