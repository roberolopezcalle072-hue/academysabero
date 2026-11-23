import {
  BadRequestException, Controller, ForbiddenException, Get, Header, Headers, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../access/application/resolve-access';
import { bearerToken } from '../access/presentation/bearer-token';
import { createAcademyClient } from '../../platform/supabase/academy-client';
import { requiredEnv } from '../../config';

/** Cifras del panel de administración (la base de datos exige que quien pregunta sea administrador). */
@Controller('admin')
export class SummaryController {
  constructor(private readonly access: ResolveAccess) {}

  @Get('summary')
  @Header('Cache-Control', 'private, no-store')
  async summary(@Headers('authorization') authorization?: string) {
    const client = await this.client(authorization);
    const { data, error } = await client.rpc('academy_admin_summary');
    return this.result(data, error);
  }

  /** Lista paginada de pagos (20 por página). */
  @Get('payments')
  @Header('Cache-Control', 'private, no-store')
  async payments(@Headers('authorization') authorization: string | undefined, @Query('filter') filter = 'paid', @Query('page') page = '1') {
    if (!['paid', 'other', 'all'].includes(filter) || !/^[1-9]\d{0,4}$/.test(page)) throw new BadRequestException();
    const client = await this.client(authorization);
    const { data, error } = await client.rpc('academy_admin_payments', { p_filter: filter, p_page: Number(page) });
    return this.result(data, error);
  }

  private async client(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(() => { throw new ServiceUnavailableException(); });
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return createAcademyClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY'), token);
  }

  private result(data: unknown, error: { code?: string } | null) {
    if (error) {
      if (error.code === '42501') throw new ForbiddenException();
      if (error.code === '22023') throw new BadRequestException();
      throw new ServiceUnavailableException();
    }
    return data;
  }
}
