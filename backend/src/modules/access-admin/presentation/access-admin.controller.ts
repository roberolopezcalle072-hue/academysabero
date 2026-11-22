import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import { ManageAccess } from '../application/manage-access';

@Controller('admin/access')
export class AccessAdminController {
  constructor(private readonly access: ResolveAccess, private readonly admin: ManageAccess) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async list(@Headers('authorization') authorization?: string, @Query('page') page = '1') {
    const token = await this.requireAdmin(authorization);
    if (!/^[1-9]\d{0,5}$/.test(page)) throw new BadRequestException();
    return this.admin.list(token, Number(page)).catch(providerError);
  }

  @Post('emails')
  @Header('Cache-Control', 'private, no-store')
  async setEmail(@Headers('authorization') authorization: string | undefined, @Body('email') email: unknown, @Body('active') active: unknown) {
    const token = await this.requireAdmin(authorization);
    if (typeof active !== 'boolean') throw new BadRequestException();
    await this.admin.setEmail(token, normalizeEmail(email), active).catch(providerError);
    return { saved: true };
  }

  @Post('assignments')
  @Header('Cache-Control', 'private, no-store')
  async assign(
    @Headers('authorization') authorization: string | undefined, @Body('email') email: unknown,
    @Body('courseId') course: unknown, @Body('requireCode') requireCode: unknown,
  ) {
    const token = await this.requireAdmin(authorization);
    if (typeof requireCode !== 'boolean' || typeof course !== 'string' ||
        !/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(course)) {
      throw new BadRequestException();
    }
    return this.admin.assign(token, normalizeEmail(email), course, requireCode).catch(providerError);
  }

  @Get('students')
  @Header('Cache-Control', 'private, no-store')
  async students(
    @Headers('authorization') authorization: string | undefined,
    @Query('q') q = '', @Query('page') page = '1',
  ) {
    const token = await this.requireAdmin(authorization);
    if (!/^[1-9]\d{0,5}$/.test(page) || typeof q !== 'string' || q.length > 120) throw new BadRequestException();
    return this.admin.students(token, q, Number(page)).catch(providerError);
  }

  @Post('students/:id/password')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async resetPassword(
    @Headers('authorization') authorization: string | undefined,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    const token = await this.requireAdmin(authorization);
    return this.admin.resetPassword(token, id).catch((error: unknown) => {
      const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : null;
      if (code === '23503') throw new NotFoundException();
      return providerError(error);
    });
  }

  private async requireAdmin(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(providerError);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

function normalizeEmail(value: unknown): string {
  if (typeof value !== 'string') throw new BadRequestException();
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new BadRequestException();
  return email;
}

function providerError(error: unknown): never {
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : null;
  if (code === '42501') throw new ForbiddenException();
  if (code === '23503' || code === '23505' || code === '23514') throw new ConflictException();
  throw new ServiceUnavailableException();
}
