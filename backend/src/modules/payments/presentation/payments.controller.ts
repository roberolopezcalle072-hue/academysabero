import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, HttpException, Inject, Logger, NotFoundException, Param, ParseUUIDPipe, Post, ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { bearerToken } from '../../access/presentation/bearer-token';
import type { PaymentProvider } from '../application/payment-provider';
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
  ) {}

  /** Indica si hay pasarela activa y qué datos públicos necesita el navegador. */
  @Get('config')
  @Header('Cache-Control', 'no-store')
  config() {
    if (!this.provider) return { enabled: false };
    return { enabled: true, provider: this.provider.name, ...this.provider.clientConfig() };
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
    @Param('id', ParseUUIDPipe) id: string, @Body('token') cardToken: unknown,
  ) {
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
        token: cardToken,
      });
    } catch (error) {
      // No se sabe si la pasarela cobró: el pago queda "processing" para revisarlo a mano, no se marca como fallido.
      this.log.error(`Pasarela sin respuesta para el pago ${id}: ${(error as Error).message}`);
      throw new ServiceUnavailableException({ reason: 'provider-unavailable' });
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
    return { status: 'paid' };
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
