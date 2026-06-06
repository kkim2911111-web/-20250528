import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { dispatchPushScenario } from './push_scenarios.ts';

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

/** Android google-services.json 과 동일해야 FCM 토큰 발송이 성공합니다. */
const ANDROID_FCM_PROJECT_ID = 'danji-26a2f';

type FcmErrorBody = {
  error?: {
    message?: string;
    details?: Array<{ errorCode?: string }>;
  };
};

export type FcmPushData = Record<string, string>;

const RESERVATION_TITLE = '예약이 완료되었습니다 🚗';

function reservationBody(vehicleName: string): string {
  return `[${vehicleName}] 예약이 확정되었습니다. 대여 시 운전면허증을 준비해주세요.`;
}

function getServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!raw) return null;
  return JSON.parse(raw) as ServiceAccount;
}

function resolveProjectId(sa: ServiceAccount): string {
  const override = Deno.env.get('FIREBASE_PROJECT_ID')?.trim();
  const projectId = override || sa.project_id;
  if (projectId !== ANDROID_FCM_PROJECT_ID) {
    console.warn(
      `FCM project_id=${projectId} — Android 앱 토큰은 ${ANDROID_FCM_PROJECT_ID} 프로젝트 기준입니다. ` +
        'Firebase Console(danji-26a2f) 서비스 계정 JSON을 FIREBASE_SERVICE_ACCOUNT_JSON에 설정하세요.',
    );
  }
  return projectId;
}

async function pruneInvalidToken(
  admin: SupabaseClient,
  token: string,
): Promise<void> {
  const { error } = await admin.from('fcm_tokens').delete().eq('token', token);
  if (error) {
    console.error('FCM token prune failed:', error.message);
  }
}

async function importPKCS8Key(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const { create, getNumericDate } = await import(
    'https://deno.land/x/djwt@v2.9.1/mod.ts'
  );

  const key = await importPKCS8Key(sa.private_key);
  const jwt = await create(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60),
    },
    key,
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error_description || 'Google OAuth token failed');
  }
  return data.access_token as string;
}

function stringData(data?: FcmPushData): Record<string, string> {
  if (!data) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(data)) {
    if (v != null && String(v).length > 0) {
      out[k] = String(v);
    }
  }
  return out;
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: FcmPushData | undefined,
  admin: SupabaseClient,
): Promise<boolean> {
  const payloadData = stringData(data);

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: payloadData,
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: 'danjicar_high_importance',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                'content-available': 1,
              },
            },
          },
          webpush: {
            headers: { Urgency: 'high' },
            notification: {
              title,
              body,
              icon: '/icons/Icon-192.png',
            },
          },
        },
      }),
    },
  );

  const responseText = await res.text();
  if (!res.ok) {
    console.error(`FCM send failed (project=${projectId}):`, responseText);
    try {
      const parsed = JSON.parse(responseText) as FcmErrorBody;
      const errorCode = parsed.error?.details?.[0]?.errorCode;
      if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
        await pruneInvalidToken(admin, token);
      }
    } catch {
      // ignore JSON parse errors
    }
    return false;
  }
  return true;
}

async function fetchUserTokens(
  admin: SupabaseClient,
  userId: string,
): Promise<string[]> {
  const { data: rows, error } = await admin
    .from('fcm_tokens')
    .select('token')
    .eq('user_id', userId);

  if (error) {
    console.error('FCM token fetch failed:', error.message);
    return [];
  }

  return (rows ?? [])
    .map((row) => row.token as string)
    .filter((t) => t && t.length > 0);
}

export async function sendPushToUser(params: {
  admin: SupabaseClient;
  userId: string;
  title: string;
  body: string;
  data?: FcmPushData;
}): Promise<{ sent: number; skipped?: boolean; tokens: number }> {
  const sa = getServiceAccount();
  if (!sa) {
    console.warn('FCM skipped: FIREBASE_SERVICE_ACCOUNT_JSON not set');
    return { sent: 0, skipped: true, tokens: 0 };
  }

  const tokens = await fetchUserTokens(params.admin, params.userId);
  if (!tokens.length) {
    return { sent: 0, tokens: 0 };
  }

  const accessToken = await getGoogleAccessToken(sa);
  const projectId = resolveProjectId(sa);
  let sent = 0;

  for (const token of tokens) {
    const ok = await sendToToken(
      accessToken,
      projectId,
      token,
      params.title,
      params.body,
      params.data,
      params.admin,
    );
    if (ok) sent += 1;
  }

  if (tokens.length > 0 && sent === 0) {
    console.warn(
      `FCM sendPushToUser: 0/${tokens.length} sent for user=${params.userId}`,
    );
  }

  return { sent, tokens: tokens.length };
}

async function fetchComplexStaffUserIds(
  admin: SupabaseClient,
  complexId: string,
): Promise<string[]> {
  const { data, error } = await admin
    .from('staff_users')
    .select('user_id')
    .eq('complex_id', complexId)
    .eq('approved', true);

  if (error) {
    console.error('staff_users fetch failed:', error.message);
    return [];
  }

  return (data ?? [])
    .map((row) => row.user_id as string)
    .filter((id) => id && id.length > 0);
}

export async function sendPushToComplexStaff(params: {
  admin: SupabaseClient;
  complexId: string;
  title: string;
  body: string;
  data?: FcmPushData;
}): Promise<{ sent: number; skipped?: boolean; staffCount: number }> {
  const sa = getServiceAccount();
  if (!sa) {
    console.warn('FCM skipped: FIREBASE_SERVICE_ACCOUNT_JSON not set');
    return { sent: 0, skipped: true, staffCount: 0 };
  }

  const staffIds = await fetchComplexStaffUserIds(params.admin, params.complexId);
  if (!staffIds.length) {
    return { sent: 0, staffCount: 0 };
  }

  const accessToken = await getGoogleAccessToken(sa);
  const projectId = resolveProjectId(sa);
  let sent = 0;

  for (const userId of staffIds) {
    const tokens = await fetchUserTokens(params.admin, userId);
    for (const token of tokens) {
      const ok = await sendToToken(
        accessToken,
        projectId,
        token,
        params.title,
        params.body,
        params.data,
        params.admin,
      );
      if (ok) sent += 1;
    }
  }

  return { sent, staffCount: staffIds.length };
}

/** @deprecated dispatchPushScenario('customer_payment_completed') 사용 */
export async function sendReservationCompletePush(params: {
  admin: SupabaseClient;
  userId: string;
  vehicleName: string;
  reservationId?: string;
}): Promise<{ sent: number; skipped?: boolean }> {
  const customer = await dispatchPushScenario({
    admin: params.admin,
    scenario: 'customer_payment_completed',
    payload: {
      userId: params.userId,
      vehicleName: params.vehicleName,
      reservationId: params.reservationId ?? '',
    },
  });

  return { sent: customer.customerSent, skipped: customer.skipped };
}
