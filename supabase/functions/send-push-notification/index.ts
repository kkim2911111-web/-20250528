import { handleCors, jsonResponse } from '../_shared/http.ts';
import { sendPushToUser } from '../_shared/fcm.ts';
import { getAdminClient, getUserFromRequest } from '../_shared/payment.ts';

/** 관리자(staff_users) → 특정 유저 FCM 푸시 발송 */
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

    const { data: profile } = await admin
      .from('user_profiles')
      .select('is_super_admin')
      .eq('user_id', caller.id)
      .maybeSingle();

    const isSuperAdmin = profile?.is_super_admin === true;

    if (!isSuperAdmin) {
      const { data: staff, error: staffError } = await admin
        .from('staff_users')
        .select('id')
        .eq('user_id', caller.id)
        .eq('approved', true)
        .maybeSingle();

      if (staffError || !staff) {
        return jsonResponse({ error: '관리자 권한이 필요합니다.' }, 403);
      }
    }

    const body = await req.json();
    const userId = body.userId?.toString()?.trim();
    const title = body.title?.toString()?.trim();
    const message = body.body?.toString()?.trim();
    const type = body.type?.toString()?.trim();
    const reservationId = body.reservationId?.toString()?.trim();

    if (!userId) {
      return jsonResponse({ error: 'userId 가 필요합니다.' }, 400);
    }
    if (!title) {
      return jsonResponse({ error: 'title 이 필요합니다.' }, 400);
    }
    if (!message) {
      return jsonResponse({ error: 'body 가 필요합니다.' }, 400);
    }

    const data: Record<string, string> = {};
    if (type) data.type = type;
    if (reservationId) data.reservation_id = reservationId;

    const result = await sendPushToUser({
      admin,
      userId,
      title,
      body: message,
      data: Object.keys(data).length ? data : undefined,
    });

    const { error: inboxError } = await admin.from('notifications').insert({
      user_id: userId,
      title,
      body: message,
      type: type ?? 'manual',
      reservation_id: reservationId ?? null,
      is_read: false,
    });
    if (inboxError) {
      console.error('in-app notification save failed:', inboxError.message);
    }

    return jsonResponse({
      ok: true,
      sent: result.sent,
      tokens: result.tokens,
      skipped: result.skipped ?? false,
    });
  } catch (e) {
    const err = e as Error;
    console.error('send-push-notification failed:', err.message);
    return jsonResponse(
      { error: err.message || '푸시 발송 실패' },
      500,
    );
  }
});
