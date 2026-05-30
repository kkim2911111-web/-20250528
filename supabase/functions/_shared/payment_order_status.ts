/** payment_orders.status — payment_orders_status_check 허용값 */
export const PaymentOrderStatus = {
  pending: 'pending',
  paid: 'paid',
  failed: 'failed',
  cancelled: 'cancelled',
  legacyConfirmed: 'confirmed',
} as const;

export type PaymentOrderStatusValue =
  (typeof PaymentOrderStatus)[keyof typeof PaymentOrderStatus];

export function isPaymentOrderPaid(
  status: string | null | undefined,
): boolean {
  return (
    status === PaymentOrderStatus.paid ||
    status === PaymentOrderStatus.legacyConfirmed
  );
}

export function paymentOrderPaidUpdate(
  paymentKey: string,
  reservationId?: string | null,
) {
  const payload: Record<string, unknown> = {
    status: PaymentOrderStatus.paid,
    payment_key: paymentKey,
    has_payment_key: paymentKey.length > 0,
    updated_at: new Date().toISOString(),
  };
  if (reservationId) payload.reservation_id = reservationId;
  return payload;
}

export function paymentOrderCancelledUpdate() {
  return {
    status: PaymentOrderStatus.cancelled,
    updated_at: new Date().toISOString(),
  };
}

export function paymentOrderFailedUpdate() {
  return {
    status: PaymentOrderStatus.failed,
    updated_at: new Date().toISOString(),
  };
}
