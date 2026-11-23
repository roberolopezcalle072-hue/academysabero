import {
  Controller, ForbiddenException, Get, Header, Headers, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../access/application/resolve-access';
import { bearerToken } from '../access/presentation/bearer-token';
import { createAcademyClient } from '../../platform/supabase/academy-client';
import { requiredEnv } from '../../config';

/** Cifras del panel de administración (la base de datos exige que quien pregunta sea administrador). */
@Controller('admin/summary')
export class SummaryController {
  constructor(private readonly access: ResolveAccess) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async summary(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(() => { throw new ServiceUnavailableException(); });
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();

    const client = createAcademyClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY'), token);
    const { data, error } = await client.rpc('academy_admin_summary');
    if (error) {
      if (error.code === '42501') throw new ForbiddenException();
      throw new ServiceUnavailableException();
    }
    return data;
  }
}
