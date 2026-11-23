/**
 * Contrato que debe cumplir cualquier pasarela de pago (Culqi, Mercado Pago, Stripe, ...).
 * El resto del sistema solo conoce esta interfaz: para cambiar de pasarela se escribe un
 * adaptador nuevo y se cambia PAYMENT_PROVIDER, sin tocar la base de datos ni la web.
 */
export interface ChargeInput {
  paymentId: string;
  /** Monto en unidades normales (por ejemplo 129.00). */
  amount: number;
  currency: string;
  description: string;
  email: string;
  customer: { firstName: string; lastName: string; phone: string; country: string };
  /** Token que entrega el formulario de pago de la pasarela en el navegador. */
  token: string;
}

export type ChargeResult =
  | { status: 'paid'; externalId: string; amount: number; currency: string }
  | { status: 'declined'; reason: string };

export interface PaymentProvider {
  /** Nombre corto y estable, se guarda en la base de datos (por ejemplo "culqi"). */
  readonly name: string;
  /** Datos públicos que el navegador necesita para abrir el formulario de pago. */
  clientConfig(): Record<string, unknown>;
  /** Cobra con el token del navegador. Lanza una excepción si la pasarela no responde. */
  charge(input: ChargeInput): Promise<ChargeResult>;
}
