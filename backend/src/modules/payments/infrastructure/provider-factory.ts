import { requiredEnv } from '../../../config';
import type { PaymentProvider } from '../application/payment-provider';
import { CulqiProvider } from './culqi-provider';
import { MockProvider } from './mock-provider';

/**
 * Elige la pasarela con PAYMENT_PROVIDER. Para cambiar de proveedor: escribir un adaptador
 * que implemente PaymentProvider, registrarlo aquí y cambiar la variable de entorno.
 * Devuelve null si no hay pasarela configurada (los pagos en línea quedan desactivados).
 */
export function createPaymentProvider(): PaymentProvider | null {
  const name = (process.env.PAYMENT_PROVIDER ?? '').trim().toLowerCase();
  if (!name) return null;
  switch (name) {
    case 'culqi':
      return new CulqiProvider(requiredEnv('CULQI_PUBLIC_KEY'), requiredEnv('CULQI_SECRET_KEY'));
    case 'mock':
      if (process.env.NODE_ENV === 'production') throw new Error('PAYMENT_PROVIDER=mock is not allowed in production');
      return new MockProvider();
    default:
      throw new Error(`Unsupported PAYMENT_PROVIDER: ${name}`);
  }
}
