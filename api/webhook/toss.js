import { invokeEdgeFunction, json } from '../lib/supabase.js';

/**
 * 토스페이먼츠 웹훅 수신 (Vercel)
 * URL: POST /api/webhook/toss
 * 이벤트: PAYMENT_STATUS_CHANGED
 *
 * 토스 개발자센터 웹훅 URL 등록:
 * https://danjicar.vercel.app/api/webhook/toss
 */
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return json(res, 405, { error: 'Method not allowed' });
  }

  try {
    const body = req.body || {};
    const { eventType } = body;

    if (eventType !== 'PAYMENT_STATUS_CHANGED') {
      return json(res, 200, { ok: true, skipped: true, eventType });
    }

    const result = await invokeEdgeFunction('payment-webhook', body);
    return json(res, 200, result);
  } catch (e) {
    console.error('[webhook/toss]', e);
    return json(res, 500, {
      error: e.message || '웹훅 처리 실패',
      code: e.code,
    });
  }
}
