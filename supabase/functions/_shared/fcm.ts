import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const RESERVATION_TITLE = '예약이 완료되었습니다 🚗';

function reservationBody(vehicleName: string): string {
  return `[${vehicleName}] 예약이 확정되었습니다. 대여 시 운전면허증을 준비해주세요.`;
}

function getServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!raw) return null;
  return JSON.parse(raw) as ServiceAccount;
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const { create, getNumericDate } = await import(
    'https://deno.land/x/djwt@v3.0.2/mod.ts'
  );
  const { importPKCS8 } = await import(
    'https://deno.land/x/djwt@v3.0.2/key/mod.ts'
  );

  const key = await importPKCS8(sa.private_key, 'RS256');
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

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
): Promise<boolean> {
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

  if (!res.ok) {
    console.error('FCM send failed:', await res.text());
    return false;
  }
  return true;
}

export async function sendReservationCompletePush(params: {
  admin: SupabaseClient;
  userId: string;
  vehicleName: string;
}): Promise<{ sent: number; skipped?: boolean }> {
  const sa = getServiceAccount();
  if (!sa) {
    console.warn('FCM skipped: FIREBASE_SERVICE_ACCOUNT_JSON not set');
    return { sent: 0, skipped: true };
  }

  const vehicleName = params.vehicleName?.trim() || '차량';
  const title = RESERVATION_TITLE;
  const body = reservationBody(vehicleName);

  const { data: rows, error } = await params.admin
    .from('fcm_tokens')
    .select('token')
    .eq('user_id', params.userId);

  if (error) {
    console.error('FCM token fetch failed:', error.message);
    return { sent: 0 };
  }

  if (!rows?.length) {
    return { sent: 0 };
  }

  const accessToken = await getGoogleAccessToken(sa);
  let sent = 0;

  for (const row of rows) {
    if (!row.token) continue;
    const ok = await sendToToken(
      accessToken,
      sa.project_id,
      row.token,
      title,
      body,
    );
    if (ok) sent += 1;
  }

  return { sent };
}
