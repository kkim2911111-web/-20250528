import { handleCors, jsonResponse } from '../_shared/http.ts';
import { sendPushToUser } from '../_shared/fcm.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';

async function fetchSuperAdminUserIds(
  admin: ReturnType<typeof getAdminClient>,
): Promise<string[]> {
  const { data, error } = await admin
    .from('user_profiles')
    .select('user_id')
    .eq('is_super_admin', true);

  if (error) {
    console.error('super admin fetch failed:', error.message);
    return [];
  }

  return (data ?? [])
    .map((row) => row.user_id as string)
    .filter((id) => id && id.length > 0);
}

/** 단지관리자 정산 요청 — DB 반영 + 최고관리자 푸시·앱내 알림 */
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const caller = await getUserFromRequest(req);
    if (!caller) return jsonResponse({ error: 'Unauthorized' }, 401);

    const admin = getAdminClient();

    const { data: staff, error: staffError } = await admin
      .from('staff_users')
      .select('id, complex_id')
      .eq('user_id', caller.id)
      .eq('approved', true)
      .maybeSingle();

    if (staffError || !staff?.complex_id) {
      return jsonResponse({ error: '관리자 권한이 필요합니다.' }, 403);
    }

    const body = await req.json();
    const year = Number(body.year);
    const month = Number(body.month);
    if (!year || !month || month < 1 || month > 12) {
      return jsonResponse({ error: 'year, month 가 필요합니다.' }, 400);
    }

    const { data: rpcData, error: rpcError } = await admin.rpc(
      'request_settlement_for_staff',
      { p_year: year, p_month: month, p_user_id: caller.id },
    );

    if (rpcError) {
      const msg = rpcError.message ?? '정산 요청에 실패했습니다.';
      if (msg.includes('already_settled')) {
        return jsonResponse({ error: '이미 정산 완료된 기간입니다.' }, 400);
      }
      return jsonResponse({ error: msg }, 400);
    }

    const result = rpcData as Record<string, unknown> | null;
    const complexName =
      result?.complexName?.toString() ??
      result?.complex_name?.toString() ??
      '단지';
    const complexId =
      result?.complexId?.toString() ??
      result?.complex_id?.toString() ??
      staff.complex_id;
    const alreadyRequested = result?.alreadyRequested === true;

    const title = '정산 요청';
    const messageBody = `${complexName} · ${year}년 ${month}월 정산을 요청했습니다.`;
    const notificationType = 'admin_settlement_request';

    const superAdminIds = await fetchSuperAdminUserIds(admin);
    let pushSent = 0;

    if (!alreadyRequested) {
      await Promise.all(
        superAdminIds.map(async (userId) => {
          const push = await sendPushToUser({
            admin,
            userId,
            title,
            body: messageBody,
            data: {
              type: notificationType,
              complex_id: complexId,
              year: String(year),
              month: String(month),
            },
          });
          pushSent += push.sent;

          const { error: inboxError } = await admin.from('notifications').insert({
            user_id: userId,
            title,
            body: messageBody,
            type: notificationType,
            complex_id: complexId,
            is_read: false,
          });
          if (inboxError) {
            console.error(
              `in-app notification save failed (user=${userId}):`,
              inboxError.message,
            );
          }
        }),
      );
    }

    return jsonResponse({
      ok: true,
      alreadyRequested,
      complexName,
      year,
      month,
      superAdminsNotified: superAdminIds.length,
      pushSent,
    });
  } catch (e) {
    const err = e as Error;
    console.error('settlement-request failed:', err.message);
    return jsonResponse(
      { error: err.message || '정산 요청 실패' },
      500,
    );
  }
});
