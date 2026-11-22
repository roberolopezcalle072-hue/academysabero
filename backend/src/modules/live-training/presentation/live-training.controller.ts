import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, Inject, NotFoundException, Param, Post, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess, type AcademyRole } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import type { LiveTrainingRepository } from '../application/live-training';
import { isUuid, sessionDetails } from './session-input';

export const LIVE_TRAINING = Symbol('LiveTrainingRepository');

@Controller()
export class LiveTrainingController {
  constructor(
    @Inject(LIVE_TRAINING) private readonly training: LiveTrainingRepository,
    private readonly access: ResolveAccess,
  ) {}

  @Get('campus/sessions')
  @Header('Cache-Control', 'private, no-store')
  async agenda(@Headers('authorization') authorization?: string, @Query('page') page = '1') {
    const token = await this.authorize(authorization, 'student');
    return this.training.agenda(token, pageNumber(page)).catch(providerError);
  }

  @Get('admin/sessions')
  @Header('Cache-Control', 'private, no-store')
  async administration(
    @Headers('authorization') authorization?: string, @Query('page') page = '1', @Query('session') session?: string,
  ) {
    const token = await this.authorize(authorization, 'admin');
    if (session !== undefined && !isUuid(session)) throw new BadRequestException();
    return this.training.administration(token, pageNumber(page), session).catch(providerError);
  }

  @Get('admin/sessions/:id/attendance')
  @Header('Cache-Control', 'private, no-store')
  async roster(
    @Headers('authorization') authorization: string | undefined, @Param('id') id: string,
    @Query('page') page = '1', @Query('present') present = '0',
  ) {
    const token = await this.authorize(authorization, 'admin');
    if (!isUuid(id) || !['0', '1'].includes(present)) throw new BadRequestException();
    return this.training.roster(token, id, pageNumber(page), present === '1').catch(providerError);
  }

  @Post('admin/sessions')
  @Header('Cache-Control', 'private, no-store')
  async save(@Headers('authorization') authorization: string | undefined, @Body() raw: unknown) {
    const token = await this.authorize(authorization, 'admin');
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new BadRequestException();
    const input = raw as Record<string, unknown>;
    const id = input.id || null;
    if (id !== null && !isUuid(id)) throw new BadRequestException();
    const saved = await this.training.save(token, id, sessionDetails(input)).catch(providerError);
    if (!saved) throw new ConflictException();
    return { id: saved };
  }

  @Post('admin/sessions/:id/cancel')
  @Header('Cache-Control', 'private, no-store')
  @HttpCode(200)
  async cancel(@Headers('authorization') authorization: string | undefined, @Param('id') id: string) {
    const token = await this.authorize(authorization, 'admin');
    if (!isUuid(id)) throw new BadRequestException();
    if (!await this.training.cancel(token, id).catch(providerError)) throw new NotFoundException();
    return { cancelled: true };
  }

  @Post('admin/sessions/:id/attendance')
  @Header('Cache-Control', 'private, no-store')
  @HttpCode(200)
  async attendance(
    @Headers('authorization') authorization: string | undefined, @Param('id') id: string,
    @Body('student') student: unknown, @Body('status') status: unknown,
  ) {
    const token = await this.authorize(authorization, 'admin');
    if (!isUuid(id) || !isUuid(student) || (status !== 'present' && status !== 'absent' && status !== 'excused')) {
      throw new BadRequestException();
    }
    if (!await this.training.recordAttendance(token, id, student, status).catch(providerError)) throw new ConflictException();
    return { saved: true };
  }

  private async authorize(authorization: string | undefined, role: AcademyRole) {
    const token = bearerToken(authorization);
    const access = await this.access.execute(token).catch(providerError);
    if (access.status === 'invalid-session') throw new UnauthorizedException();
    if (access.status !== 'authorized' || access.member.role !== role) throw new ForbiddenException();
    return token;
  }
}

function pageNumber(value: string): number {
  if (typeof value !== 'string' || !/^[1-9]\d{0,5}$/.test(value)) throw new BadRequestException();
  return Number(value);
}

function providerError(error: unknown): never {
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : null;
  if (code === '42501') throw new ForbiddenException();
  if (code === '23514' || code === '23503' || code === '23502' || code === '23505') throw new ConflictException();
  throw new ServiceUnavailableException();
}
