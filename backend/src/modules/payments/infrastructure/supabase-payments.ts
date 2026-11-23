import { createAcademyClient } from '../../../platform/supabase/academy-client';

export interface StartedPayment {
  payment_id: string;
  amount: number;
  currency: string;
  course_name: string;
  email: string;
}

export interface ReservedCharge extends StartedPayment {
  full_name: string;
  phone: string;
  country: string;
}

export interface StartInput {
  courseId: string;
  fullName: string;
  phone: string;
  country: string;
  notes: string | null;
  termsVersion: string;
}

export class SupabasePayments {
  constructor(
    private readonly url: string,
    private readonly key: string,
    private readonly internalSecret: string,
  ) {}

  async start(token: string, input: StartInput, provider: string): Promise<StartedPayment> {
    const { data, error } = await this.client(token).rpc('academy_start_payment', {
      p_course: input.courseId, p_name: input.fullName, p_phone: input.phone, p_country: input.country,
      p_notes: input.notes, p_terms_version: input.termsVersion, p_provider: provider,
    });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) throw new Error('Payment was not created');
    return { ...row, amount: Number(row.amount) };
  }

  /** Reserva el pago (pending -> processing). Devuelve null si ya fue reservado o no es del alumno. */
  async reserve(token: string, paymentId: string): Promise<ReservedCharge | null> {
    const { data, error } = await this.client(token).rpc('academy_begin_charge', { p_payment: paymentId });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    return row ? { ...row, amount: Number(row.amount) } : null;
  }

  /** Datos de la constancia de un pago confirmado (solo del propio alumno o de un administrador). */
  async receipt(token: string, paymentId: string) {
    const { data, error } = await this.client(token).rpc('academy_payment_receipt', { p_payment: paymentId });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    return row ? { ...row, amount: Number(row.amount), receipt_number: row.receipt_number === null ? null : Number(row.receipt_number) } : null;
  }

  async mine(token: string) {
    const { data, error } = await this.client(token).rpc('academy_my_payments');
    if (error) throw error;
    return (data ?? []).map((row: Record<string, unknown>) => ({ ...row, amount: Number(row.amount) }));
  }

  async confirm(paymentId: string, provider: string, externalId: string, amount: number, currency: string) {
    const { error } = await this.client().rpc('academy_confirm_payment', {
      p_secret: this.internalSecret, p_payment: paymentId, p_provider: provider,
      p_external: externalId, p_amount: amount, p_currency: currency,
    });
    if (error) throw error;
  }

  async fail(paymentId: string, reason: string) {
    const { error } = await this.client().rpc('academy_fail_payment', {
      p_secret: this.internalSecret, p_payment: paymentId, p_reason: reason,
    });
    if (error) throw error;
  }

  private client(accessToken?: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
