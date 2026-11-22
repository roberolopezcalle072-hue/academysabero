import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import { SupabaseEnrollment } from '../infrastructure/supabase-enrollment';

// Versión vigente de los términos de compra. Si cambian, sube este valor.
export const TERMS_VERSION = 'v1';

@Controller()
export class EnrollmentController {
  constructor(private readonly enrollment: SupabaseEnrollment, private readonly access: ResolveAccess) {}

  /** Cursos publicados con precio. Disponible para cualquier cuenta con sesión. */
  @Get('catalog')
  @Header('Cache-Control', 'private, no-store')
  async catalog(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization);
    return this.enrollment.catalog(token).catch(providerError);
  }

  @Get('enrollment-requests/mine')
  @Header('Cache-Control', 'private, no-store')
  async mine(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization);
    return this.enrollment.mine(token).catch(providerError);
  }

  @Post('enrollment-requests')
  @HttpCode(201)
  @Header('Cache-Control', 'private, no-store')
  async request(
    @Headers('authorization') authorization: string | undefined,
    @Body() body: Record<string, unknown>,
  ) {
    const token = bearerToken(authorization);
    const { courseId, fullName, phone, country, notes, acceptTerms } = body ?? {};
    if (acceptTerms !== true) throw new BadRequestException({ reason: 'terms-required' });
    if (typeof courseId !== 'string' || !UUID.test(courseId)) throw new BadRequestException();
    const input = {
      courseId,
      fullName: text(fullName, 2, 120),
      phone: phoneNumber(phone),
      country: text(country, 2, 60),
      notes: notes === undefined || notes === null || notes === '' ? null : text(notes, 1, 1000),
      termsVersion: TERMS_VERSION,
    };
    const id = await this.enrollment.request(token, input).catch(providerError);
    return { id };
  }

  // ---- Administración ----

  @Get('admin/enrollment-requests')
  @Header('Cache-Control', 'private, no-store')
  async list(
    @Headers('authorization') authorization: string | undefined,
    @Query('status') status = 'pending', @Query('page') page = '1',
  ) {
    const token = await this.requireAdmin(authorization);
    if (!['pending', 'approved', 'rejected', 'all'].includes(status) || !/^[1-9]\d{0,5}$/.test(page)) {
      throw new BadRequestException();
    }
    return this.enrollment.pending(token, status, Number(page)).catch(providerError);
  }

  @Post('admin/enrollment-requests/:id/decision')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async decide(
    @Headers('authorization') authorization: string | undefined,
    @Param('id', ParseUUIDPipe) id: string,
    @Body('approve') approve: unknown, @Body('note') note: unknown,
  ) {
    const token = await this.requireAdmin(authorization);
    if (typeof approve !== 'boolean') throw new BadRequestException();
    const cleanNote = note === undefined || note === null || note === '' ? null : text(note, 1, 500);
    await this.enrollment.review(token, id, approve, cleanNote).catch(providerError);
    return { saved: true };
  }

  private async requireAdmin(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(providerError);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

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
  if (e.code === '23505') throw new ConflictException();
  throw new ServiceUnavailableException();
}
