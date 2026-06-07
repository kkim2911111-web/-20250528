import { handleCors, jsonResponse } from '../_shared/http.ts';
import {
  enqueueBillingRetry,
  notifyBillingPaymentFailed,
} from '../_shared/billing_retry.ts';
import {
  getAdminClient,
  getUserClient,
  getUserFromRequest,
  makeOrderId,
} from '../_shared/payment.ts';
import { cancelTossPayment, chargeTossBilling } from '../_shared/toss.ts';

const MAX_BILLING_RETRIES = 3;

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const user = await getUserFromRequest(req);
    if (!user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const body = await req.json();
    const reservationId = body?.reservationId?.toString()?.trim();
    const extensionHours = Number(body?.extensionHours ?? 1);

    if (!reservationId) {
      return jsonResponse({ error: 'reservationId 가 필요합니다.' }, 400);
    }
    if (!Number.isInteger(extensionHours) || extensionHours < 1) {
      return jsonResponse({ error: 'extensionHours 는 1 이상이어야 합니다.' }, 400);
    }

    const userClient = getUserClient(authHeader);
    const admin = getAdminClient();

    const { data: checkRaw, error: checkErr } = await userClient.rpc(
      'check_rental_extension_for_me',
      {
        p_reservation_id: reservationId,
        p_extension_hours: extensionHours,
      },
    );

    if (checkErr) {
      console.error('[billing-extension-charge] check', checkErr);
      return jsonResponse({ error: checkErr.message }, 400);
    }

    const check = checkRaw as Record<string, unknown>;
    if (check?.eligible !== true) {
      return jsonResponse(
        {
          error: (check?.message as string) ?? '연장할 수 없습니다.',
          reason: check?.reason,
        },
        400,
      );
    }

    const addedPrice = Number(check.addedPrice ?? 0);
    if (!Number.isInteger(addedPrice) || addedPrice < 0) {
      return jsonResponse({ error: '추가 요금 계산 오류' }, 500);
    }

    const { data: profile, error: profileErr } = await admin
      .from('user_profiles')
      .select('toss_billing_key, payment_card_registered')
      .eq('user_id', user.id)
      .maybeSingle();

    if (profileErr) {
      return jsonResponse({ error: profileErr.message }, 500);
    }

    const billingKey = profile?.toss_billing_key?.toString()?.trim();
    if (!billingKey || profile?.payment_card_registered !== true) {
      return jsonResponse(
        {
          error: '등록된 결제카드가 없습니다. 마이페이지에서 결제카드를 등록해주세요.',
          code: 'billing_key_missing',
        },
        400,
      );
    }

    if (addedPrice === 0) {
      const { data: applied, error: applyErr } = await userClient.rpc(
        'apply_rental_extension_for_me',
        {
          p_reservation_id: reservationId,
          p_extension_hours: extensionHours,
          p_payment_key: null,
          p_payment_order_id: null,
        },
      );
      if (applyErr) {
        return jsonResponse({ error: applyErr.message }, 400);
      }
      return jsonResponse({ ok: true, addedPrice: 0, result: applied });
    }

    const orderId = `ext_${reservationId}_${makeOrderId()}`;
    const orderName = `대여 연장 ${extensionHours}시간`;

    let paymentKey: string | null = null;
    try {
      const charge = await chargeTossBilling({
        billingKey,
        customerKey: user.id,
        amount: addedPrice,
        orderId,
        orderName,
      });
      paymentKey = charge.paymentKey;
      if (!paymentKey) {
        return jsonResponse({ error: '결제 승인 키를 받지 못했습니다.' }, 500);
      }

      const { data: applied, error: applyErr } = await userClient.rpc(
        'apply_rental_extension_for_me',
        {
          p_reservation_id: reservationId,
          p_extension_hours: extensionHours,
          p_payment_key: paymentKey,
          p_payment_order_id: orderId,
        },
      );

      if (applyErr) {
        console.error('[billing-extension-charge] apply', applyErr);
        try {
          await cancelTossPayment({
            paymentKey,
            cancelReason: '연장 적용 실패',
            cancelAmount: addedPrice,
          });
        } catch (cancelErr) {
          console.error('[billing-extension-charge] cancel', cancelErr);
        }
        return jsonResponse(
          {
            error: applyErr.message,
            code: 'extension_apply_failed',
          },
          400,
        );
      }

      return jsonResponse({
        ok: true,
        addedPrice,
        paymentKey,
        orderId,
        result: applied,
      });
    } catch (chargeErr) {
      const err = chargeErr as Error & { code?: string };
      console.error('[billing-extension-charge] charge', err);
      if (paymentKey) {
        try {
          await cancelTossPayment({
            paymentKey,
            cancelReason: '연장 처리 오류',
            cancelAmount: addedPrice,
          });
        } catch (_) {}
      }

      let complexId: string | null = null;
      try {
        const { data: resRow } = await admin
          .from('reservations')
          .select('vehicles(complex_id)')
          .eq('id', reservationId)
          .maybeSingle();
        const vehicles = resRow?.vehicles as { complex_id?: string } | null;
        complexId = vehicles?.complex_id?.toString() ?? null;
      } catch (_) {}

      try {
        await enqueueBillingRetry(admin, {
          chargeType: 'extension',
          reservationId,
          userId: user.id,
          amount: addedPrice,
          complexId,
          extensionHours,
          lastError: err.message || '결제 실패',
        });
        await notifyBillingPaymentFailed(admin, {
          chargeType: 'extension',
          reservationId,
          userId: user.id,
          amount: addedPrice,
          complexId,
          retryCount: 0,
          maxRetries: MAX_BILLING_RETRIES,
          isFinal: false,
        });
      } catch (retryErr) {
        console.error('[billing-extension-charge] retry enqueue', retryErr);
      }

      return jsonResponse(
        {
          error: err.message || '결제에 실패했습니다.',
          code: err.code ?? 'billing_charge_failed',
        },
        402,
      );
    }
  } catch (e) {
    const err = e as Error & { code?: string };
    console.error('[billing-extension-charge]', err);
    return jsonResponse(
      { error: err.message || '연장 결제 실패', code: err.code },
      500,
    );
  }
});
