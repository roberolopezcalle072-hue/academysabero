import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers, HttpCode,
  NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import { MailService } from '../../mail/mail.service';
import { SupabaseInquiries } from '../infrastructure/supabase-inquiries';

/** El administrador ve las consultas de los alumnos y las responde desde el sitio (el alumno la ve y recibe un correo). */
@Controller('admin/inquiries')
export class InquiriesController {
  constructor(
    private readonly inquiries: SupabaseInquiries,
    private readonly access: ResolveAccess,
    private readonly mail: MailService,
  ) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async list(@Headers('authorization') authorization: string | undefined, @Query('status') status = 'open', @Query('page') page = '1') {
    const token = await this.requireAdmin(authorization);
    if (!['open', 'answered', 'all'].includes(status) || !/^[1-9]\d{0,4}$/.test(page)) throw new BadRequestException();
    return this.inquiries.list(token, status, Number(page)).catch(failure);
  }

  @Post(':id/reply')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async reply(
    @Headers('authorization') authorization: string | undefined,
    @Param('id', ParseUUIDPipe) id: string, @Body('body') body: unknown,
  ) {
    const token = await this.requireAdmin(authorization);
    if (typeof body !== 'string' || !body.trim() || body.trim().length > 5000) throw new BadRequestException();
    const reply = body.trim().replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
    const target = await this.inquiries.reply(token, id, reply).catch(failure);
    // El alumno recibe la respuesta por correo; si el correo falla, la respuesta ya quedó guardada.
    void this.mail.inquiryAnswered({ to: target.student_email, name: target.student_name, subject: target.subject, reply, key: `${id}-${Date.now()}` });
    return { saved: true };
  }

  private async requireAdmin(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(failure);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

function failure(error: unknown): never {
  if (error instanceof ForbiddenException || error instanceof UnauthorizedException || error instanceof NotFoundException) throw error;
  const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code: string }).code : '';
  if (code === '42501') throw new ForbiddenException();
  if (code === '23503') throw new NotFoundException();
  if (code === '23514' || code === '22023') throw new BadRequestException();
  if (code === '23505') throw new ConflictException();
  throw new ServiceUnavailableException();
}
