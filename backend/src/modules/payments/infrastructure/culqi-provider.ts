import { Logger } from '@nestjs/common';
import type { ChargeInput, ChargeResult, PaymentProvider } from '../application/payment-provider';

type Fetch = typeof fetch;

interface CulqiCharge {
  id?: string;
  capture?: boolean | null;
  amount?: number;
  currency_code?: string;
  object?: string;
  action_code?: string;
  type?: string;
  code?: string;
  decline_code?: string;
  param?: string;
  outcome?: { type?: string; code?: string; user_message?: string; merchant_message?: string };
  user_message?: string;
  merchant_message?: string;
}

/** Adaptador de Culqi (https://docs.culqi.com): Checkout en el navegador -> token -> cargo desde el servidor. */
export class CulqiProvider implements PaymentProvider {
  readonly name = 'culqi';
  private readonly log = new Logger('Culqi');

  constructor(
    private readonly publicKey: string,
    private readonly secretKey: string,
    private readonly baseUrl = 'https://api.culqi.com/v2',
    private readonly http: Fetch = fetch,
  ) {
    if (!/^pk_(test|live)_/.test(publicKey)) throw new Error('CULQI_PUBLIC_KEY must start with pk_test_ or pk_live_');
    if (!/^sk_(test|live)_/.test(secretKey)) throw new Error('CULQI_SECRET_KEY must start with sk_test_ or sk_live_');
    // Evita mezclar llaves de prueba y de producción.
    if (publicKey.startsWith('pk_live_') !== secretKey.startsWith('sk_live_')) {
      throw new Error('Culqi keys must both be test or both be live');
    }
  }

  clientConfig() {
    return { publicKey: this.publicKey };
  }

  async charge(input: ChargeInput): Promise<ChargeResult> {
    const response = await this.http(`${this.baseUrl}/charges`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(input.amount * 100),
        currency_code: input.currency,
        email: input.email,
        source_id: input.token,
        // Captura explícita: sin esto Culqi puede dejar el cargo solo autorizado y el dinero no se cobra.
        capture: true,
        description: input.description.slice(0, 80),
        metadata: { payment_id: input.paymentId },
        antifraud_details: {
          first_name: input.customer.firstName,
          last_name: input.customer.lastName,
          phone_number: input.customer.phone.replace(/[^\d]/g, '').slice(0, 15),
          ...(input.deviceId ? { device_finger_print_id: input.deviceId } : {}),
        },
        ...(input.authentication3DS ? { authentication_3DS: input.authentication3DS } : {}),
      }),
      signal: AbortSignal.timeout(20_000),
    });

    const body = await response.json().catch(() => ({})) as CulqiCharge;
    if (response.status >= 500) throw new Error(`Culqi unavailable (${response.status})`);

    if (response.ok && body.outcome?.type === 'venta_exitosa' && body.id) {
      // Defensa adicional: si el cargo quedó solo autorizado, se captura ahora; si no se logra, se avisa (queda en revisión).
      if (body.capture !== true) await this.capture(body.id);
      return {
        status: 'paid',
        externalId: body.id,
        amount: (body.amount ?? 0) / 100,
        currency: body.currency_code ?? input.currency,
      };
    }
    // La tarjeta exige 3D Secure (Culqi responde 200 con action_code REVIEW): hay que autenticar y reintentar.
    if (response.ok && body.action_code === 'REVIEW' && !input.authentication3DS) {
      this.log.log(JSON.stringify({ event: 'authentication-required', currency: input.currency, amount: input.amount }));
      return { status: 'authentication-required' };
    }
    // Motivo técnico para el comercio (no contiene datos de tarjeta ni llaves).
    this.log.warn(JSON.stringify({
      event: 'charge-declined', http: response.status, currency: input.currency, amount: input.amount,
      type: body.type ?? body.outcome?.type, code: body.code ?? body.outcome?.code, decline: body.decline_code,
      param: body.param, merchant: body.merchant_message ?? body.outcome?.merchant_message,
    }));
    return {
      status: 'declined',
      reason: body.user_message ?? body.outcome?.user_message ?? 'El pago fue rechazado.',
    };
  }

  private async capture(chargeId: string): Promise<void> {
    const response = await this.http(`${this.baseUrl}/charges/${encodeURIComponent(chargeId)}/capture`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(20_000),
    });
    const body = await response.json().catch(() => ({})) as CulqiCharge;
    if (!response.ok || body.capture !== true) throw new Error(`Culqi capture failed (${response.status}) for ${chargeId}`);
  }
}
