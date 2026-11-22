import {
  BadRequestException, Body, Controller, ForbiddenException, Get, Header, Headers, HttpCode, HttpException,
  NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../access/application/resolve-access';
import { bearerToken } from '../access/presentation/bearer-token';
import { SupabaseComplaints } from './supabase-complaints';

const DOC_TYPES = ['DNI', 'CE', 'PASAPORTE', 'RUC', 'OTRO'];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Freno general (en memoria) contra envíos masivos: el límite por correo está además en la base de datos.
const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = 40;
let windowStart = Date.now();
let windowCount = 0;

@Controller()
export class ComplaintsController {
  constructor(private readonly complaints: SupabaseComplaints, private readonly access: ResolveAccess) {}

  /** Libro de Reclamaciones virtual: público, no exige cuenta. */
  @Post('complaints')
  @HttpCode(201)
  @Header('Cache-Control', 'no-store')
  async submit(@Body() body: Record<string, unknown>) {
    if (Date.now() - windowStart > WINDOW_MS) { windowStart = Date.now(); windowCount = 0; }
    if (++windowCount > MAX_PER_WINDOW) throw new HttpException({ reason: 'rate-limited' }, 429);

    const b = body ?? {};
    const kind = b.kind === 'queja' ? 'queja' : b.kind === 'reclamo' ? 'reclamo' : null;
    if (!kind) throw new BadRequestException();
    const docType = typeof b.docType === 'string' && DOC_TYPES.includes(b.docType) ? b.docType : null;
    if (!docType) throw new BadRequestException();
    const email = text(b.email, 5, 254).toLowerCase();
    if (!EMAIL.test(email)) throw new BadRequestException();
    const isMinor = b.isMinor === true;
    const guardian = isMinor ? text(b.guardian, 2, 120) : null;
    if (b.acceptTruth !== true) throw new BadRequestException({ reason: 'declaration-required' });

    try {
      const code = await this.complaints.submit({
        kind, docType, email, isMinor, guardian,
        fullName: text(b.fullName, 2, 120),
        docNumber: text(b.docNumber, 4, 20),
        address: text(b.address, 5, 200),
        phone: text(b.phone, 6, 30),
        service: text(b.service, 3, 200),
        amount: b.amount === undefined || b.amount === null || b.amount === '' ? null : text(b.amount, 1, 40),
        detail: text(b.detail, 10, 2000),
        request: text(b.request, 5, 1000),
      });
      return { code };
    } catch (error) {
      const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code: string }).code : '';
      if (code === '54000') throw new HttpException({ reason: 'too-many' }, 429);
      if (code === '23514' || code === '22001') throw new BadRequestException();
      throw new ServiceUnavailableException();
    }
  }

  @Get('admin/complaints')
  @Header('Cache-Control', 'private, no-store')
  async list(@Headers('authorization') authorization: string | undefined, @Query('status') status = 'open', @Query('page') page = '1') {
    const token = await this.requireAdmin(authorization);
    if (!['open', 'answered', 'all'].includes(status) || !/^[1-9]\d{0,5}$/.test(page)) throw new BadRequestException();
    return this.complaints.list(token, status, Number(page)).catch(adminError);
  }

  @Post('admin/complaints/:id/answer')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async answer(
    @Headers('authorization') authorization: string | undefined,
    @Param('id', ParseUUIDPipe) id: string, @Body('response') response: unknown,
  ) {
    const token = await this.requireAdmin(authorization);
    await this.complaints.answer(token, id, text(response, 5, 3000)).catch((error: unknown) => {
      const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code: string }).code : '';
      if (code === '23503') throw new NotFoundException();
      return adminError(error);
    });
    return { saved: true };
  }

  private async requireAdmin(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(adminError);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

function text(value: unknown, min: number, max: number): string {
  if (typeof value !== 'string') throw new BadRequestException();
  const clean = value.trim().replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
  if (clean.length < min || clean.length > max) throw new BadRequestException();
  return clean;
}

function adminError(error: unknown): never {
  if (error instanceof ForbiddenException || error instanceof UnauthorizedException || error instanceof NotFoundException) throw error;
  const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code: string }).code : '';
  if (code === '42501') throw new ForbiddenException();
  throw new ServiceUnavailableException();
}
