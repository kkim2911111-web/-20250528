import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient } from '../_shared/payment.ts';
import { dispatchPushScenario } from '../_shared/push_scenarios.ts';

type VehicleRow = {
  id: string;
  model_name?: string | null;
  car_number?: string | null;
  complex_id?: string | null;
  insurance_expires_at?: string | null;
  insurance_warn_7d_sent_at?: string | null;
};

function todayKst(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
}

function addDaysKst(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T12:00:00+09:00`);
  d.setDate(d.getDate() + days);
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const admin = getAdminClient();
    const today = todayKst();
    const warnTarget = addDaysKst(today, 7);

    const { data: vehicles, error } = await admin
      .from('vehicles')
      .select(
        'id, model_name, car_number, complex_id, insurance_expires_at, insurance_warn_7d_sent_at',
      )
      .not('insurance_expires_at', 'is', null);

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    let warned = 0;
    let disabled = 0;

    for (const raw of vehicles ?? []) {
      const v = raw as VehicleRow;
      const expires = v.insurance_expires_at?.toString()?.slice(0, 10);
      if (!expires) continue;

      const vehicleLabel = [
        v.model_name?.trim() || '차량',
        v.car_number?.trim(),
      ].filter(Boolean).join(' ');

      const complexId = v.complex_id?.toString();
      if (!complexId) continue;

      if (expires === warnTarget && v.insurance_warn_7d_sent_at !== warnTarget) {
        try {
          await dispatchPushScenario({
            admin,
            scenario: 'staff_insurance_expiring_soon',
            payload: {
              complexId,
              vehicleName: vehicleLabel,
              endAt: expires,
            },
          });
          await admin
            .from('vehicles')
            .update({
              insurance_warn_7d_sent_at: warnTarget,
              updated_at: new Date().toISOString(),
            })
            .eq('id', v.id);
          warned++;
        } catch (e) {
          console.error('[scheduled-vehicle-insurance] warn', v.id, e);
        }
      }

      if (expires <= today) {
        try {
          await dispatchPushScenario({
            admin,
            scenario: 'staff_insurance_expired',
            payload: {
              complexId,
              vehicleName: vehicleLabel,
              endAt: expires,
            },
          });
          disabled++;
        } catch (e) {
          console.error('[scheduled-vehicle-insurance] disable', v.id, e);
        }
      }
    }

    return jsonResponse({
      ok: true,
      today,
      warnTarget,
      warned,
      disabled,
    });
  } catch (e) {
    const err = e as Error;
    console.error('[scheduled-vehicle-insurance]', err);
    return jsonResponse({ error: err.message }, 500);
  }
});
