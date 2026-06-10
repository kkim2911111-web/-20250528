import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export async function isAppMaintenanceEnabled(
  admin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await admin
    .from('app_settings')
    .select('value')
    .eq('key', 'maintenance_mode')
    .maybeSingle();

  if (error) {
    console.error('[maintenance] read failed:', error.message);
    return false;
  }

  const value = data?.value as { enabled?: boolean } | null;
  return value?.enabled === true;
}

export async function userBypassesAppMaintenance(
  admin: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data: profile } = await admin
    .from('user_profiles')
    .select('is_super_admin')
    .eq('user_id', userId)
    .maybeSingle();

  if (profile?.is_super_admin === true) return true;

  const { data: staff } = await admin
    .from('staff_users')
    .select('user_id')
    .eq('user_id', userId)
    .eq('approved', true)
    .maybeSingle();

  return staff?.user_id != null;
}

export async function assertResidentMaintenanceAllowed(
  admin: SupabaseClient,
  userId: string,
): Promise<void> {
  if (await userBypassesAppMaintenance(admin, userId)) return;
  if (await isAppMaintenanceEnabled(admin)) {
    const err = new Error('maintenance_active') as Error & { code?: string };
    err.code = 'maintenance_active';
    throw err;
  }
}
