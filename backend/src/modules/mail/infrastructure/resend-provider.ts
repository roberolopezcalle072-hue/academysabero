import type { EmailProvider, OutgoingEmail } from '../application/email-provider';

type Fetch = typeof fetch;

/** Adaptador de Resend (https://resend.com/docs/api-reference/emails/send-email). */
export class ResendProvider implements EmailProvider {
  readonly name = 'resend';

  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly http: Fetch = fetch,
    private readonly baseUrl = 'https://api.resend.com',
  ) {
    if (!/^re_[A-Za-z0-9_]+$/.test(apiKey)) throw new Error('RESEND_API_KEY must start with re_');
    if (!/<?[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+>?$/.test(from)) throw new Error('EMAIL_FROM is not a valid sender');
  }

  async send(email: OutgoingEmail): Promise<void> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
    };
    if (email.idempotencyKey) headers['Idempotency-Key'] = email.idempotencyKey.slice(0, 256);

    const response = await this.http(`${this.baseUrl}/emails`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        from: this.from,
        to: email.to,
        subject: email.subject,
        html: email.html,
        text: email.text,
        ...(email.replyTo ? { reply_to: email.replyTo } : {}),
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({})) as { message?: string; name?: string };
      throw new Error(`Resend ${response.status}${body.name ? ` ${body.name}` : ''}: ${body.message ?? 'error al enviar'}`);
    }
  }
}
