import type { ChargeInput, ChargeResult, PaymentProvider } from '../application/payment-provider';

/** Simulador SOLO para desarrollo y pruebas. Nunca se activa con NODE_ENV=production. */
export class MockProvider implements PaymentProvider {
  readonly name = 'mock';

  clientConfig() {
    return { sandbox: true };
  }

  async charge(input: ChargeInput): Promise<ChargeResult> {
    // Simula una tarjeta que exige 3D Secure: primero pide autenticar y, con el resultado, cobra.
    if (input.token === 'tok_mock_3ds') {
      if (!input.authentication3DS) return { status: 'authentication-required' };
      return { status: 'paid', externalId: `mock_${input.paymentId}`, amount: input.amount, currency: input.currency };
    }
    if (input.token === 'tok_mock_ok') {
      return { status: 'paid', externalId: `mock_${input.paymentId}`, amount: input.amount, currency: input.currency };
    }
    return { status: 'declined', reason: 'Tarjeta de prueba rechazada.' };
  }
}
