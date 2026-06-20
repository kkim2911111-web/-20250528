import { handleCors, jsonResponse } from '../_shared/http.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';
import {
  type PushScenario,
  dispatchPushScenario,
} from '../_shared/push_scenarios.ts';

const USER_TRIGGER_SCENARIOS: Set<PushScenario> = new Set([
  'customer_signup_complete',
  'customer_reservation_confirmed',
  'customer_reservation_cancelled',
  'customer_rental_started',
  'customer_no_show_auto_completed',
  'staff_new_signup',
  'staff_license_review_request',
  'staff_resident_review_request',
  'staff_new_reservation',
  'staff_reservation_cancelled',
  'staff_rental_started',
  'staff_return_completed',
  'staff_no_show_auto_completed',
  'customer_return_overdue',
  'staff_return_overdue',
]);

const STAFF_ONLY_SCENARIOS: Set<PushScenario> = new Set([
  'customer_license_approved',
  'customer_license_rejected',
  'customer_resident_approved',
  'customer_resident_rejected',
  'customer_payment_completed',
  'customer_return_inspection_complete',
  'staff_conflict_risk',
]);

const SYSTEM_SCENARIOS: Set<PushScenario> = new Set([
  ...USER_TRIGGER_SCENARIOS,
  ...STAFF_ONLY_SCENARIOS,
  'customer_rental_start_10min',
  'customer_return_10min',
  'customer_return_10min_next_booking',
  'customer_return_overdue',
]);

async function assertApprovedStaff(
  admin: ReturnType<typeof getAdminClient>,
  userId: string,
): Promise<boolean> {
  const { data } = await admin
    .from('staff_users')
    .select('id')
    .eq('user_id', userId)
    .eq('approved', true)
    .maybeSingle();
  return !!data;
}

async function assertResidentInComplex(
  admin: ReturnType<typeof getAdminClient>,
  userId: string,
  complexId: string,
): Promise<boolean> {
  const { data } = await admin
    .from('residents')
    .select('id')
    .eq('user_id', userId)
    .eq('complex_id', complexId)
    .maybeSingle();
  return !!data;
}

function payloadFromBody(body: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(body)) {
    if (key === 'scenario') continue;
    if (value == null) continue;
    out[key] = String(value);
  }
  return out;
}

/** 시나리오 기반 FCM 발송 (클라이언트·Edge Function·스케줄러) */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const body = await req.json();
    const scenario = body.scenario?.toString() as PushScenario;
    if (!scenario || !SYSTEM_SCENARIOS.has(scenario)) {
      return jsonResponse({ error: '유효하지 않은 scenario 입니다.' }, 400);
    }

    const admin = getAdminClient();
    const payload = payloadFromBody(body);

    const authHeader = req.headers.get('Authorization') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const isServiceCall = serviceKey.length > 0 &&
      authHeader === `Bearer ${serviceKey}`;

    if (!isServiceCall) {
      const caller = await getUserFromRequest(req);
      if (!caller) return jsonResponse({ error: 'Unauthorized' }, 401);

      if (STAFF_ONLY_SCENARIOS.has(scenario)) {
        const ok = await assertApprovedStaff(admin, caller.id);
        if (!ok) {
          return jsonResponse({ error: '관리자 권한이 필요합니다.' }, 403);
        }
      } else if (USER_TRIGGER_SCENARIOS.has(scenario)) {
        if (
          scenario === 'customer_signup_complete' ||
          scenario === 'customer_reservation_confirmed' ||
          scenario === 'customer_reservation_cancelled' ||
          scenario === 'customer_rental_started'
        ) {
          payload.userId = caller.id;
        } else if (scenario.startsWith('staff_')) {
          const complexId = payload.complexId;
          if (!complexId) {
            return jsonResponse({ error: 'complexId 가 필요합니다.' }, 400);
          }
          const ok = await assertResidentInComplex(
            admin,
            caller.id,
            complexId,
          );
          if (!ok) {
            return jsonResponse({ error: '단지 정보가 일치하지 않습니다.' }, 403);
          }
        }
      } else {
        return jsonResponse({ error: 'Forbidden scenario' }, 403);
      }
    }

    const result = await dispatchPushScenario({
      admin,
      scenario,
      payload,
    });

    return jsonResponse({
      ok: true,
      scenario,
      customerSent: result.customerSent,
      staffSent: result.staffSent,
      skipped: result.skipped ?? false,
    });
  } catch (e) {
    const err = e as Error;
    console.error('dispatch-push-scenario failed:', err.message);
    return jsonResponse({ error: err.message || '푸시 발송 실패' }, 500);
  }
});
