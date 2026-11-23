/**
 * Contrato de cualquier servicio de envío de correo (Resend, Brevo, SMTP, ...).
 * Para cambiar de proveedor se escribe un adaptador nuevo y se cambia EMAIL_PROVIDER.
 */
export interface OutgoingEmail {
  to: string[];
  subject: string;
  html: string;
  text: string;
  replyTo?: string;
  /** Evita enviar dos veces el mismo correo si se reintenta. */
  idempotencyKey?: string;
}

export interface EmailProvider {
  readonly name: string;
  send(email: OutgoingEmail): Promise<void>;
}
