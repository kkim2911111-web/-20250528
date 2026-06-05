import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  type FcmPushData,
  sendPushToComplexStaff,
  sendPushToUser,
} from './fcm.ts';

export type PushScenario =
  // 고객
  | 'customer_signup_complete'
  | 'customer_license_approved'
  | 'customer_license_rejected'
  | 'customer_resident_approved'
  | 'customer_resident_rejected'
  | 'customer_reservation_confirmed'
  | 'customer_reservation_cancelled'
  | 'customer_payment_completed'
  | 'customer_rental_start_10min'
  | 'customer_return_10min'
  | 'customer_return_10min_next_booking'
  | 'customer_return_overdue'
  | 'customer_return_inspection_complete'
  // 관리자(단지 staff 전원)
  | 'staff_new_signup'
  | 'staff_license_review_request'
  | 'staff_resident_review_request'
  | 'staff_new_reservation'
  | 'staff_reservation_cancelled'
  | 'staff_rental_started'
  | 'staff_return_completed'
  | 'staff_return_overdue'
  | 'staff_conflict_risk';

export type PushMessage = {
  title: string;
  body: string;
  data: FcmPushData;
};

function fmtDateTime(iso?: string | null): string {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    return d.toLocaleString('ko-KR', {
      timeZone: 'Asia/Seoul',
      month: 'numeric',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  } catch {
    return iso;
  }
}

export function buildPushMessage(
  scenario: PushScenario,
  payload: Record<string, string> = {},
): PushMessage {
  const vehicle = payload.vehicleName?.trim() || '차량';
  const when = fmtDateTime(payload.startAt ?? payload.endAt);
  const reason = payload.reason?.trim() || '관리자 확인 필요';
  const renter = payload.renterName?.trim() || '임차인';
  const points = payload.pointsEarned?.trim();

  const data: FcmPushData = { type: scenario };
  if (payload.reservationId) data.reservation_id = payload.reservationId;
  if (payload.userId) data.user_id = payload.userId;

  switch (scenario) {
    case 'customer_signup_complete':
      return {
        title: '단지카 가입을 환영합니다',
        body: '차량 공유 서비스를 시작해보세요.',
        data: { ...data, type: 'home' },
      };
    case 'customer_license_approved':
      return {
        title: '면허 인증이 완료됐습니다',
        body: '이제 차량을 예약할 수 있습니다.',
        data: { ...data, type: 'booking' },
      };
    case 'customer_license_rejected':
      return {
        title: '면허 인증이 거절됐습니다',
        body: reason,
        data: { ...data, type: 'license' },
      };
    case 'customer_resident_approved':
      return {
        title: '입주민 인증이 완료됐습니다',
        body: '서비스 이용이 가능합니다.',
        data: { ...data, type: 'home' },
      };
    case 'customer_resident_rejected':
      return {
        title: '입주민 인증이 거절됐습니다',
        body: reason,
        data: { ...data, type: 'resident' },
      };
    case 'customer_reservation_confirmed':
      return {
        title: '예약이 확정됐습니다',
        body: when
          ? `[${vehicle}] ${when} 예약이 확정됐습니다.`
          : `[${vehicle}] 예약이 확정됐습니다.`,
        data: { ...data, type: 'reservation' },
      };
    case 'customer_reservation_cancelled':
      return {
        title: '예약이 취소됐습니다',
        body: `[${vehicle}] 예약이 취소됐습니다.`,
        data: { ...data, type: 'reservation' },
      };
    case 'customer_payment_completed':
      return {
        title: '결제가 완료됐습니다',
        body: points
          ? `결제가 완료됐습니다. ${points}포인트가 적립됩니다.`
          : '결제가 완료됐습니다. 포인트가 적립됩니다.',
        data: { ...data, type: 'reservation' },
      };
    case 'customer_rental_start_10min':
      return {
        title: '곧 대여가 시작됩니다',
        body: '10분 후 대여가 시작됩니다.',
        data: { ...data, type: 'reservation' },
      };
    case 'customer_return_10min':
      return {
        title: '반납 시간이 다가옵니다',
        body: '제때 반납 부탁드립니다.',
        data: { ...data, type: 'reservation' },
      };
    case 'customer_return_10min_next_booking':
      return {
        title: '반납 시간이 다가옵니다',
        body:
          '다음 예약이 있습니다. 반납이 불가할 시 고객센터로 연락주세요.',
        data: { ...data, type: 'reservation' },
      };
    case 'customer_return_overdue':
      return {
        title: '반납이 지연되고 있습니다',
        body: '즉시 반납 또는 고객센터 연락 요청',
        data: { ...data, type: 'reservation' },
      };
    case 'customer_return_inspection_complete':
      return {
        title: '반납이 확인됐습니다',
        body: '정상 반납 처리됐습니다.',
        data: { ...data, type: 'reservation' },
      };
    case 'staff_new_signup':
      return {
        title: '새 입주민이 가입했습니다',
        body: '단지 신규 가입자 발생',
        data: { ...data, type: 'admin' },
      };
    case 'staff_license_review_request':
      return {
        title: '면허 심사 요청이 있습니다',
        body: '확인이 필요합니다.',
        data: { ...data, type: 'admin_license' },
      };
    case 'staff_resident_review_request':
      return {
        title: '입주민 인증 요청이 있습니다',
        body: '확인이 필요합니다.',
        data: { ...data, type: 'admin_resident' },
      };
    case 'staff_new_reservation':
      return {
        title: '새 예약이 들어왔습니다',
        body: when
          ? `[${vehicle}] ${when}`
          : `[${vehicle}] 새 예약`,
        data: { ...data, type: 'admin_reservation' },
      };
    case 'staff_reservation_cancelled':
      return {
        title: '예약이 취소됐습니다',
        body: `[${vehicle}] 예약 취소`,
        data: { ...data, type: 'admin_reservation' },
      };
    case 'staff_rental_started':
      return {
        title: '대여가 시작됐습니다',
        body: `[${vehicle}] ${renter}`,
        data: { ...data, type: 'admin_reservation' },
      };
    case 'staff_return_completed':
      return {
        title: '반납이 완료됐습니다',
        body: `[${vehicle}] 반납 완료`,
        data: { ...data, type: 'admin_reservation' },
      };
    case 'staff_return_overdue':
      return {
        title: '반납이 지연되고 있습니다',
        body: `[${vehicle}] ${renter}`,
        data: { ...data, type: 'admin_reservation' },
      };
    case 'staff_conflict_risk':
      return {
        title: '예약 충돌 위험이 있습니다',
        body: payload.nextStartAt
          ? `[${vehicle}] 다음 예약 ${fmtDateTime(payload.nextStartAt)}`
          : `[${vehicle}] 다음 예약과 시간이 겹칠 수 있습니다.`,
        data: { ...data, type: 'admin_reservation' },
      };
    default:
      return {
        title: '단지카 알림',
        body: '새 알림이 있습니다.',
        data,
      };
  }
}

export async function resolveComplexId(
  admin: SupabaseClient,
  payload: Record<string, string>,
): Promise<string | null> {
  if (payload.complexId) return payload.complexId;

  if (payload.reservationId) {
    const { data } = await admin
      .from('reservations')
      .select('vehicle_id, vehicles(complex_id)')
      .eq('id', payload.reservationId)
      .maybeSingle();
    const vehicles = data?.vehicles as { complex_id?: string } | null;
    return vehicles?.complex_id?.toString() ?? null;
  }

  if (payload.userId) {
    const { data } = await admin
      .from('residents')
      .select('complex_id')
      .eq('user_id', payload.userId)
      .maybeSingle();
    return data?.complex_id?.toString() ?? null;
  }

  return null;
}

const STAFF_SCENARIOS: Set<PushScenario> = new Set([
  'staff_new_signup',
  'staff_license_review_request',
  'staff_resident_review_request',
  'staff_new_reservation',
  'staff_reservation_cancelled',
  'staff_rental_started',
  'staff_return_completed',
  'staff_return_overdue',
  'staff_conflict_risk',
]);

export async function dispatchPushScenario(params: {
  admin: SupabaseClient;
  scenario: PushScenario;
  payload?: Record<string, string>;
}): Promise<{ customerSent: number; staffSent: number; skipped?: boolean }> {
  const payload = params.payload ?? {};
  const message = buildPushMessage(params.scenario, payload);

  let customerSent = 0;
  let staffSent = 0;

  if (STAFF_SCENARIOS.has(params.scenario)) {
    const complexId = await resolveComplexId(params.admin, payload);
    if (!complexId) {
      return { customerSent: 0, staffSent: 0 };
    }
    const staffResult = await sendPushToComplexStaff({
      admin: params.admin,
      complexId,
      title: message.title,
      body: message.body,
      data: message.data,
    });
    staffSent = staffResult.sent;
    return {
      customerSent,
      staffSent,
      skipped: staffResult.skipped,
    };
  }

  const userId = payload.userId;
  if (!userId) {
    return { customerSent: 0, staffSent: 0 };
  }

  const userResult = await sendPushToUser({
    admin: params.admin,
    userId,
    title: message.title,
    body: message.body,
    data: message.data,
  });

  customerSent = userResult.sent;
  return {
    customerSent,
    staffSent,
    skipped: userResult.skipped,
  };
}
