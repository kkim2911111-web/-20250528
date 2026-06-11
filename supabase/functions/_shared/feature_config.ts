import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  assertResidentMaintenanceAllowed,
  userBypassesAppMaintenance,
} from './maintenance_mode.ts';

export async function isAppFeatureEnabled(
  admin: SupabaseClient,
  featureKey: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from('app_config')
    .select('is_enabled')
    .eq('feature_key', featureKey)
    .maybeSingle();

  if (error) {
    console.error('[feature_config] read failed:', error.message);
    return true;
  }

  return data?.is_enabled !== false;
}

export async function assertAppFeatureEnabled(
  admin: SupabaseClient,
  userId: string,
  featureKey: string,
): Promise<void> {
  await assertResidentMaintenanceAllowed(admin, userId);

  if (await userBypassesAppMaintenance(admin, userId)) return;

  if (!(await isAppFeatureEnabled(admin, featureKey))) {
    const err = new Error('feature_disabled') as Error & { code?: string };
    err.code = 'feature_disabled';
    throw err;
  }
}
