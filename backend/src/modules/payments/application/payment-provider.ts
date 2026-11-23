/**
 * Contrato que debe cumplir cualquier pasarela de pago (Culqi, Mercado Pago, Stripe, ...).
 * El resto del sistema solo conoce esta interfaz: para cambiar de pasarela se escribe un
 * adaptador nuevo y se cambia PAYMENT_PROVIDER, sin tocar la base de datos ni la web.
 */
/** Resultado de la verificación 3D Secure que entrega la pasarela en el navegador. */
export interface Authentication3DS {
  eci: string;
  xid: string;
  cavv: string;
  protocolVersion: string;
  directoryServerTransactionId?: string;
}

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
  /** Huella del dispositivo (antifraude). Debe ser la misma en el cobro y en su reintento tras el 3D Secure. */
  deviceId?: string;
  /** Presente solo en el reintento posterior a la verificación 3D Secure. */
  authentication3DS?: Authentication3DS;
}

export type ChargeResult =
  | { status: 'paid'; externalId: string; amount: number; currency: string }
  | { status: 'declined'; reason: string }
  /** La tarjeta exige 3D Secure: el navegador debe autenticar y reintentar el cobro con el mismo token. */
  | { status: 'authentication-required' };

export interface PaymentProvider {
  /** Nombre corto y estable, se guarda en la base de datos (por ejemplo "culqi"). */
  readonly name: string;
  /** Datos públicos que el navegador necesita para abrir el formulario de pago. */
  clientConfig(): Record<string, unknown>;
  /** Cobra con el token del navegador. Lanza una excepción si la pasarela no responde. */
  charge(input: ChargeInput): Promise<ChargeResult>;
}
