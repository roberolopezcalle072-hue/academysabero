import { BadRequestException, Body, Controller, Get, Headers, HttpCode, Post, Req, UnauthorizedException } from '@nestjs/common';
import { bearerToken } from '../access/presentation/bearer-token';
import { AuthService, type RequestInfo } from './auth.service';

const text = (value: unknown, max = 200): string => {
  if (typeof value !== 'string' || value.length > max) throw new BadRequestException('Datos no válidos');
  return value;
};

interface Request { ip?: string; headers: Record<string, string | string[] | undefined> }

const info = (req: Request): RequestInfo => ({
  ip: req.ip ?? 'unknown',
  userAgent: typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : null,
});

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Get('config')
  config() {
    return { google: this.auth.googleEnabled };
  }

  @Post('signup')
  signUp(@Body() body: Record<string, unknown>, @Req() req: Request) {
    return this.auth.signUp(text(body.email, 254), text(body.password, 200), text(body.name ?? '', 120), info(req));
  }

  @Post('login') @HttpCode(200)
  login(@Body() body: Record<string, unknown>, @Req() req: Request) {
    return this.auth.login(text(body.email, 254), text(body.password, 200), info(req));
  }

  @Post('google') @HttpCode(200)
  google(@Body() body: Record<string, unknown>, @Req() req: Request) {
    return this.auth.loginWithGoogle(text(body.code, 2000), text(body.codeVerifier, 200), text(body.redirectUri, 500), info(req));
  }

  @Post('refresh') @HttpCode(200)
  refresh(@Body() body: Record<string, unknown>) {
    return this.auth.refresh(text(body.refreshToken, 200));
  }

  @Post('logout') @HttpCode(204)
  async logout(@Headers('authorization') authorization?: string) {
    const who = await this.authenticate(authorization);
    await this.auth.logout(who.sessionId);
  }

  @Get('me')
  async me(@Headers('authorization') authorization?: string) {
    const who = await this.authenticate(authorization);
    return this.auth.me(who.userId);
  }

  @Post('password') @HttpCode(204)
  async password(@Body() body: Record<string, unknown>, @Headers('authorization') authorization?: string) {
    const who = await this.authenticate(authorization);
    await this.auth.changePassword(who.userId, who.sessionId, text(body.current ?? '', 200), text(body.password, 200));
  }

  private async authenticate(authorization?: string) {
    const who = await this.auth.verify(bearerToken(authorization));
    if (!who) throw new UnauthorizedException();
    return who;
  }
}
