import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, HttpException, Inject, Logger, NotFoundException, Param, ParseUUIDPipe, Post, ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { bearerToken } from '../../access/presentation/bearer-token';
import type { Authentication3DS, PaymentProvider } from '../application/payment-provider';
import { MailService } from '../../mail/mail.service';
import { SupabasePayments } from '../infrastructure/supabase-payments';

export const PAYMENT_PROVIDER = Symbol('PaymentProvider');
const TERMS_VERSION = 'v1';
const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

@Controller('payments')
export class PaymentsController {
  private readonly log = new Logger('Payments');

  constructor(
    @Inject(PAYMENT_PROVIDER) private readonly provider: PaymentProvider | null,
    private readonly payments: SupabasePayments,
    private readonly mail: MailService,
  ) {}

  /** Indica si hay pasarela activa y qué datos públicos necesita el navegador. */
  @Get('config')
  @Header('Cache-Control', 'no-store')
  config() {
    if (!this.provider) return { enabled: false };
    return { enabled: true, provider: this.provider.name, ...this.provider.clientConfig() };
  }

  @Get('mine')
  @Header('Cache-Control', 'private, no-store')
  async mine(@Headers('authorization') authorization?: string) {
    return this.payments.mine(bearerToken(authorization)).catch(providerError);
  }

  @Get(':id/receipt')
  @Header('Cache-Control', 'private, no-store')
  async receipt(@Headers('authorization') authorization: string | undefined, @Param('id', ParseUUIDPipe) id: string) {
    const row = await this.payments.receipt(bearerToken(authorization), id).catch(providerError);
    if (!row) throw new NotFoundException();
    return row;
  }

  @Post('start')
  @HttpCode(201)
  @Header('Cache-Control', 'private, no-store')
  async start(@Headers('authorization') authorization: string | undefined, @Body() body: Record<string, unknown>) {
    const token = bearerToken(authorization);
    const provider = this.requireProvider();
    const { courseId, fullName, phone, country, notes, acceptTerms } = body ?? {};
    if (acceptTerms !== true) throw new BadRequestException({ reason: 'terms-required' });
    if (typeof courseId !== 'string' || !UUID.test(courseId)) throw new BadRequestException();

    const started = await this.payments.start(token, {
      courseId,
      fullName: text(fullName, 2, 120),
      phone: phoneNumber(phone),
      country: text(country, 2, 60),
      notes: notes === undefined || notes === null || notes === '' ? null : text(notes, 1, 1000),
      termsVersion: TERMS_VERSION,
    }, provider.name).catch(providerError);

    return {
      paymentId: started.payment_id,
      provider: provider.name,
      config: provider.clientConfig(),
      amount: started.amount,
      amountMinor: Math.round(started.amount * 100),
      currency: started.currency,
      title: started.course_name,
      email: started.email,
    };
  }

  @Post(':id/charge')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async charge(
    @Headers('authorization') authorization: string | undefined,
    @Param('id', ParseUUIDPipe) id: string, @Body() body: Record<string, unknown>,
  ) {
    const cardToken = body?.token;
    const deviceId = body?.deviceId === undefined ? undefined : validDevice(body.deviceId);
    const authentication3DS = body?.authentication3DS === undefined ? undefined : validAuthentication(body.authentication3DS);
    const token = bearerToken(authorization);
    const provider = this.requireProvider();
    if (typeof cardToken !== 'string' || !/^[A-Za-z0-9_-]{6,120}$/.test(cardToken)) throw new BadRequestException();

    // Reserva el pago: un segundo clic o una segunda pestaña no puede cobrarlo otra vez.
    const row = await this.payments.reserve(token, id).catch(providerError);
    if (!row) throw new ConflictException({ reason: 'payment-not-open' });

    const [firstName, ...rest] = row.full_name.split(/\s+/);
    let result;
    try {
      result = await provider.charge({
        paymentId: id, amount: row.amount, currency: row.currency, description: row.course_name, email: row.email,
        customer: { firstName, lastName: rest.join(' ') || firstName, phone: row.phone, country: row.country },
        token: cardToken, deviceId, authentication3DS,
      });
    } catch (error) {
      // No se sabe si la pasarela cobró: el pago queda "processing" para revisarlo a mano, no se marca como fallido.
      this.log.error(`Pasarela sin respuesta para el pago ${id}: ${(error as Error).message}`);
      throw new ServiceUnavailableException({ reason: 'provider-unavailable' });
    }

    if (result.status === 'authentication-required') {
      // La tarjeta pide 3D Secure: el pago vuelve a "pending" y el navegador reintenta con el resultado.
      try {
        await this.payments.release(id);
      } catch (error) {
        this.log.error(`No se pudo liberar el pago ${id} para el 3D Secure: ${(error as Error).message}`);
        throw new ServiceUnavailableException({ reason: 'provider-unavailable' });
      }
      return { status: 'authentication-required', provider: provider.name };
    }

    if (result.status === 'declined') {
      await this.payments.fail(id, result.reason).catch((e) => this.log.error(`No se pudo marcar el pago ${id} como fallido: ${e?.message}`));
      throw new HttpException({ reason: 'declined', message: result.reason }, 402);
    }

    if (result.amount !== row.amount || result.currency !== row.currency) {
      this.log.error(`Monto distinto en el pago ${id}: esperado ${row.amount} ${row.currency}, cobrado ${result.amount} ${result.currency} (${result.externalId})`);
      throw new ConflictException({ reason: 'amount-mismatch' });
    }

    try {
      await this.payments.confirm(id, provider.name, result.externalId, row.amount, row.currency);
    } catch (error) {
      // Dinero cobrado pero matrícula sin activar: queda registrado para conciliar a mano.
      this.log.error(`COBRADO SIN CONFIRMAR pago=${id} ${provider.name}=${result.externalId}: ${(error as Error).message}`);
      throw new ServiceUnavailableException({ reason: 'confirm-failed', reference: result.externalId });
    }
    // Los correos se envían aparte: si fallan, el pago ya está confirmado y el alumno ya tiene acceso.
    void this.notifyPaid(token, id, row, result.externalId);
    return { status: 'paid' };
  }

  private async notifyPaid(
    token: string, id: string,
    row: { full_name: string; email: string; course_name: string; amount: number; currency: string; country: string },
    reference: string,
  ) {
    try {
      const receipt = await this.payments.receipt(token, id).catch(() => null);
      await Promise.all([
        this.mail.paymentConfirmed({
          to: row.email, name: row.full_name, course: row.course_name, amount: row.amount, currency: row.currency,
          receiptNumber: receipt?.receipt_number ?? null, paymentId: id, paidAt: receipt?.paid_at ?? new Date().toISOString(),
        }),
        this.mail.adminPayment({
          name: row.full_name, email: row.email, course: row.course_name, amount: row.amount,
          currency: row.currency, country: row.country, reference,
        }),
      ]);
    } catch (error) {
      this.log.error(`No se pudieron enviar los correos del pago ${id}: ${(error as Error).message}`);
    }
  }

  private requireProvider(): PaymentProvider {
    if (!this.provider) throw new ServiceUnavailableException({ reason: 'payments-unavailable' });
    return this.provider;
  }
}

function text(value: unknown, min: number, max: number): string {
  if (typeof value !== 'string') throw new BadRequestException();
  const clean = value.trim().replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
  if (clean.length < min || clean.length > max) throw new BadRequestException();
  return clean;
}

function validDevice(value: unknown): string {
  if (typeof value !== 'string' || !UUID.test(value)) throw new BadRequestException();
  return value;
}

function validAuthentication(value: unknown): Authentication3DS {
  const v = (typeof value === 'object' && value !== null ? value : {}) as Record<string, unknown>;
  const field = (key: string, pattern: RegExp, optional = false): string | undefined => {
    const item = v[key];
    if (item === undefined || item === null || item === '') {
      if (optional) return undefined;
      throw new BadRequestException();
    }
    if (typeof item !== 'string' || !pattern.test(item)) throw new BadRequestException();
    return item;
  };
  return {
    eci: field('eci', /^\d{1,2}$/)!,
    xid: field('xid', /^[A-Za-z0-9+/=_-]{1,200}$/)!,
    cavv: field('cavv', /^[A-Za-z0-9+/=_-]{1,200}$/)!,
    protocolVersion: field('protocolVersion', /^\d+(\.\d+){0,2}$/)!,
    directoryServerTransactionId: field('directoryServerTransactionId', /^[A-Za-z0-9-]{1,100}$/, true),
  };
}

function phoneNumber(value: unknown): string {
  const clean = text(value, 6, 30);
  if (!/^[+\d][\d\s()-]{5,29}$/.test(clean)) throw new BadRequestException();
  return clean;
}

function providerError(error: unknown): never {
  if (error instanceof ForbiddenException || error instanceof UnauthorizedException) throw error;
  const e = typeof error === 'object' && error !== null ? error as { code?: string; status?: number } : {};
  if (e.status === 401 || e.code === 'PGRST301' || e.code === 'PGRST303') throw new UnauthorizedException();
  if (e.code === '42501') throw new ForbiddenException();
  if (e.code === '23503') throw new NotFoundException();
  if (e.code === '23505' || e.code === '23514') throw new ConflictException();
  throw new ServiceUnavailableException();
}
