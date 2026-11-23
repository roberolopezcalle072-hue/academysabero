import { Inject, Injectable, Logger } from '@nestjs/common';
import type { EmailProvider, OutgoingEmail } from './application/email-provider';

export const EMAIL_PROVIDER = Symbol('EmailProvider');

const esc = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string
));
const nl2br = (value: string) => esc(value).replace(/\r?\n/g, '<br>');

function money(amount: number, currency: string) {
  return new Intl.NumberFormat(currency === 'PEN' ? 'es-PE' : 'en-US', { style: 'currency', currency }).format(amount);
}

function dateTime(iso: string | Date) {
  return new Intl.DateTimeFormat('es-PE', { dateStyle: 'long', timeStyle: 'short', timeZone: 'America/Lima' }).format(new Date(iso));
}

/** Envía los correos del sistema. Nunca lanza errores: un correo caído no debe romper un pago ni un reclamo. */
@Injectable()
export class MailService {
  private readonly log = new Logger('Mail');
  private readonly site = (process.env.SITE_URL?.trim() || 'https://academy.saberoconsulting.com').replace(/\/+$/, '');
  private readonly admin = process.env.EMAIL_ADMIN_TO?.trim() || 'gerencia@saberoconsulting.com';

  constructor(@Inject(EMAIL_PROVIDER) private readonly provider: EmailProvider | null) {}

  get enabled() { return this.provider !== null; }

  // ---------------- Pagos ----------------
  paymentConfirmed(input: { to: string; name: string; course: string; amount: number; currency: string; receiptNumber: number | null; paymentId: string; paidAt: string }) {
    const total = money(input.amount, input.currency);
    const number = input.receiptNumber ? `N.º ${String(input.receiptNumber).padStart(6, '0')}` : '';
    return this.deliver({
      to: [input.to],
      subject: `¡Pago confirmado! Ya tienes acceso a ${input.course}`,
      idempotencyKey: `pago-${input.paymentId}`,
      replyTo: this.admin,
      ...this.render({
        title: '¡Pago confirmado!',
        intro: `Hola ${esc(input.name)}, recibimos tu pago y tu acceso al curso ya está activo.`,
        rows: [['Curso', input.course], ['Importe', total], ['Constancia', number || '—'], ['Fecha', dateTime(input.paidAt)]],
        buttons: [['Ir a mi campus', `${this.site}/campus`], ['Ver constancia de pago', `${this.site}/cuenta/comprobante/${input.paymentId}`]],
        note: 'Para obtener un resultado funcional necesitarás contratar por tu cuenta un servidor VPS, un dominio, un plan de suscripción, códigos o licencias y DeepSeek. Te asesoramos en cada paso. La boleta o factura electrónica se emite por separado.',
      }),
    });
  }

  adminPayment(input: { name: string; email: string; course: string; amount: number; currency: string; country: string; reference: string }) {
    return this.deliver({
      to: [this.admin],
      subject: `Nuevo pago: ${input.name} · ${money(input.amount, input.currency)}`,
      idempotencyKey: `pago-admin-${input.reference}`,
      ...this.render({
        title: 'Nuevo pago recibido',
        intro: 'Se confirmó un pago y la matrícula ya está activa.',
        rows: [['Alumno', input.name], ['Correo', input.email], ['País', input.country], ['Curso', input.course], ['Importe', money(input.amount, input.currency)], ['Referencia de la pasarela', input.reference]],
        buttons: [['Ver solicitudes', `${this.site}/admin/solicitudes?estado=all`]],
        note: 'Recuerda emitir la boleta o factura electrónica en SUNAT si corresponde.',
      }),
    });
  }

  // ---------------- Consultas del campus ----------------
  /** Aviso al administrador: al pulsar "Responder" en el correo, la respuesta va directo al alumno. */
  adminInquiry(input: { key: string; name: string; email: string; subject: string; body: string; createdAt: string }) {
    return this.deliver({
      to: [this.admin],
      subject: `Consulta de ${input.name}: ${input.subject}`.replace(/[\r\n<>]+/g, ' ').slice(0, 150),
      idempotencyKey: `consulta-admin-${input.key}`,
      replyTo: input.email,
      ...this.render({
        title: 'Nueva consulta de un alumno',
        intro: 'Un alumno escribió desde el campus. Puedes responder a este correo y le llegará directamente a él.',
        rows: [['Alumno', input.name], ['Correo', input.email], ['Fecha', dateTime(input.createdAt)], ['Asunto', input.subject]],
        blocks: [['Mensaje', input.body]],
        buttons: [['Responder por correo', `mailto:${encodeURIComponent(input.email)}?subject=${encodeURIComponent('Re: ' + input.subject)}`]],
        note: '',
      }),
    });
  }

  inquiryAnswered(input: { key: string; to: string; name: string; subject: string; reply: string }) {
    return this.deliver({
      to: [input.to],
      subject: `Respuesta a tu consulta: ${input.subject}`.replace(/[\r\n<>]+/g, ' ').slice(0, 150),
      idempotencyKey: `consulta-resp-${input.key}`,
      replyTo: this.admin,
      ...this.render({
        title: 'Respondimos tu consulta',
        intro: `Hola ${esc(input.name)}, el equipo de SABERO Academy respondió tu consulta.`,
        rows: [['Asunto', input.subject]],
        blocks: [['Respuesta', input.reply]],
        buttons: [['Ver en mi campus', `${this.site}/campus/consultas`]],
        note: 'Puedes responder a este correo si necesitas algo más.',
      }),
    });
  }

  inquiryReceived(input: { key: string; to: string; name: string; subject: string; body: string }) {
    return this.deliver({
      to: [input.to],
      subject: 'Recibimos tu consulta',
      idempotencyKey: `consulta-${input.key}`,
      replyTo: this.admin,
      ...this.render({
        title: 'Recibimos tu consulta',
        intro: `Hola ${esc(input.name)}, tu mensaje llegó al equipo de SABERO Academy. Te responderemos a este correo lo antes posible.`,
        rows: [['Asunto', input.subject]],
        blocks: [['Tu mensaje', input.body]],
        buttons: [['Ir a mi campus', `${this.site}/campus/consultas`]],
        note: '',
      }),
    });
  }

  // ---------------- Libro de Reclamaciones ----------------
  complaintReceived(input: { to: string; code: string; kind: string; name: string; service: string; detail: string; request: string; createdAt: string }) {
    const kind = input.kind === 'queja' ? 'queja' : 'reclamo';
    return this.deliver({
      to: [input.to],
      subject: `Recibimos tu ${kind} ${input.code}`,
      idempotencyKey: `reclamo-${input.code}`,
      replyTo: this.admin,
      ...this.render({
        title: `Hoja de Reclamación ${input.code}`,
        intro: `Hola ${esc(input.name)}, registramos tu ${kind}. Esta es tu copia. Te responderemos a este correo dentro del plazo que establece la ley.`,
        rows: [['Código', input.code], ['Tipo', kind], ['Fecha', dateTime(input.createdAt)], ['Servicio', input.service]],
        blocks: [['Detalle', input.detail], ['Pedido del consumidor', input.request]],
        buttons: [],
        note: 'Conserva este correo como constancia.',
      }),
    });
  }

  adminComplaint(input: { code: string; kind: string; name: string; email: string; detail: string }) {
    return this.deliver({
      to: [this.admin],
      subject: `Nuevo ${input.kind === 'queja' ? 'queja' : 'reclamo'} ${input.code}`,
      idempotencyKey: `reclamo-admin-${input.code}`,
      ...this.render({
        title: `Nuevo ${input.kind === 'queja' ? 'queja' : 'reclamo'} en el Libro de Reclamaciones`,
        intro: 'Hay un reclamo pendiente de respuesta.',
        rows: [['Código', input.code], ['Consumidor', input.name], ['Correo', input.email]],
        blocks: [['Detalle', input.detail]],
        buttons: [['Responder en el panel', `${this.site}/admin/reclamos`]],
        note: '',
      }),
    });
  }

  complaintAnswered(input: { to: string; code: string; name: string; response: string }) {
    return this.deliver({
      to: [input.to],
      subject: `Respuesta a tu reclamación ${input.code}`,
      idempotencyKey: `reclamo-resp-${input.code}`,
      replyTo: this.admin,
      ...this.render({
        title: `Respuesta a ${input.code}`,
        intro: `Hola ${esc(input.name)}, esta es la respuesta a tu hoja de reclamación.`,
        rows: [['Código', input.code]],
        blocks: [['Respuesta', input.response]],
        buttons: [],
        note: 'Si no estás conforme, puedes acudir al Indecopi u otras vías de solución de controversias.',
      }),
    });
  }

  // ---------------- Solicitudes manuales ----------------
  adminRequest(input: { name: string; email: string; phone: string; country: string; course: string }) {
    return this.deliver({
      to: [this.admin],
      subject: `Nueva solicitud de inscripción: ${input.name}`,
      ...this.render({
        title: 'Nueva solicitud de inscripción',
        intro: 'Un alumno envió su solicitud y espera tu validación.',
        rows: [['Alumno', input.name], ['Correo', input.email], ['Teléfono', input.phone], ['País', input.country], ['Curso', input.course]],
        buttons: [['Revisar solicitud', `${this.site}/admin/solicitudes`]],
        note: '',
      }),
    });
  }

  // ---------------- Interno ----------------
  private async deliver(email: OutgoingEmail): Promise<void> {
    if (!this.provider) {
      this.log.warn(`Correo no enviado (no hay proveedor configurado): "${email.subject}"`);
      return;
    }
    try {
      await this.provider.send(email);
    } catch (error) {
      this.log.error(`No se pudo enviar "${email.subject}": ${(error as Error).message}`);
    }
  }

  private render(opts: {
    title: string; intro: string; rows: [string, string][]; blocks?: [string, string][];
    buttons: [string, string][]; note: string;
  }): { html: string; text: string } {
    const rows = opts.rows.map(([k, v]) => `<tr><td style="padding:8px 0;color:#53667a;font-size:14px;width:38%;vertical-align:top">${esc(k)}</td><td style="padding:8px 0;color:#071b35;font-size:14px;font-weight:600">${esc(v)}</td></tr>`).join('');
    const blocks = (opts.blocks ?? []).map(([k, v]) => `<p style="margin:18px 0 4px;color:#53667a;font-size:13px">${esc(k)}</p><p style="margin:0;color:#182638;font-size:15px;line-height:1.6;background:#f5f8f9;border-radius:10px;padding:12px 14px">${nl2br(v)}</p>`).join('');
    const buttons = opts.buttons.map(([label, url], i) => `<a href="${esc(url)}" style="display:inline-block;margin:6px 8px 6px 0;padding:12px 22px;border-radius:999px;font-weight:700;font-size:15px;text-decoration:none;${i === 0 ? 'background:#0b7bff;color:#ffffff' : 'background:#eaf3ff;color:#0a5fd1'}">${esc(label)}</a>`).join('');
    const html = `<!doctype html><html lang="es"><body style="margin:0;background:#eef3f7;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef3f7;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:18px;overflow:hidden;border:1px solid #dde6ed">
<tr><td style="background:#ffffff;padding:22px 28px;border-bottom:1px solid #dde6ed"><img src="${esc(this.site)}/logos/logoapp.png" alt="SABERO Academy" height="44" style="display:block;height:44px;width:auto"></td></tr>
<tr><td style="padding:28px">
<h1 style="margin:0 0 10px;color:#071b35;font-size:24px;line-height:1.2">${esc(opts.title)}</h1>
<p style="margin:0 0 18px;color:#182638;font-size:15px;line-height:1.6">${opts.intro}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #dde6ed">${rows}</table>
${blocks}
${buttons ? `<p style="margin:22px 0 0">${buttons}</p>` : ''}
${opts.note ? `<p style="margin:22px 0 0;color:#53667a;font-size:13px;line-height:1.6">${esc(opts.note)}</p>` : ''}
</td></tr>
<tr><td style="background:#071b35;padding:18px 28px;color:#b7c6d6;font-size:12px;line-height:1.6">SABERO Academy · <a href="${esc(this.site)}" style="color:#8ec5ff">${esc(this.site.replace(/^https?:\/\//, ''))}</a><br><a href="${esc(this.site)}/libro-de-reclamaciones" style="color:#8ec5ff">Libro de Reclamaciones</a> · <a href="${esc(this.site)}/privacidad" style="color:#8ec5ff">Privacidad</a></td></tr>
</table></td></tr></table></body></html>`;
    const strip = (s: string) => s.replace(/<br\s*\/?>/g, '\n').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
    const text = [
      opts.title, '', strip(opts.intro), '',
      ...opts.rows.map(([k, v]) => `${k}: ${v}`),
      ...(opts.blocks ?? []).flatMap(([k, v]) => ['', `${k}:`, v]),
      ...opts.buttons.flatMap(([label, url]) => ['', `${label}: ${url}`]),
      ...(opts.note ? ['', opts.note] : []),
      '', `SABERO Academy · ${this.site}`,
    ].join('\n');
    return { html, text };
  }
}
