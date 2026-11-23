import { requiredEnv } from '../../../config';
import type { EmailProvider } from '../application/email-provider';
import { ResendProvider } from './resend-provider';

/**
 * Elige el servicio de correo con EMAIL_PROVIDER. Devuelve null si no hay ninguno configurado:
 * el sistema funciona igual, solo que no envía correos (queda registrado en el log).
 */
export function createEmailProvider(): EmailProvider | null {
  const name = (process.env.EMAIL_PROVIDER ?? '').trim().toLowerCase();
  if (!name) return null;
  switch (name) {
    case 'resend':
      return new ResendProvider(
        requiredEnv('RESEND_API_KEY'),
        process.env.EMAIL_FROM?.trim() || 'SABERO Academy <no-reply@saberoconsulting.com>',
      );
    default:
      throw new Error(`Unsupported EMAIL_PROVIDER: ${name}`);
  }
}
