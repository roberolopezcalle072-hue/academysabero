import {
  BadRequestException, Body, Controller, ForbiddenException, Get, Header, Headers,
  HttpCode, Post, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../application/resolve-access';
import { bearerToken } from './bearer-token';

@Controller('access')
export class AccessController {
  constructor(private readonly resolveAccess: ResolveAccess) {}

  @Get('me')
  @Header('Cache-Control', 'private, no-store')
  async getMember(@Headers('authorization') authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.resolveAccess.execute(token).catch(() => {
      throw new ServiceUnavailableException();
    });
    if (result.status === 'authorized') return result.member;
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    throw new ForbiddenException({ reason: result.status });
  }

  @Post('redeem')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async redeem(@Headers('authorization') authorization: string | undefined, @Body('code') code: unknown) {
    const token = bearerToken(authorization);
    if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{32,128}$/.test(code)) {
      throw new BadRequestException();
    }
    const result = await this.resolveAccess.redeem(token, code).catch(() => {
      throw new ServiceUnavailableException();
    });
    if (result === 'invalid-session') throw new UnauthorizedException();
    if (result === 'rejected') throw new ForbiddenException();
    return { accepted: true };
  }
}
