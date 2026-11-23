import {
  BadRequestException, ConflictException, ForbiddenException, HttpException, HttpStatus,
  ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import type { AuthConfig } from './auth.config';
import type { AuthRepository, UserRow } from './auth.repository';
import { GoogleOAuth, GoogleRejected } from './google-oauth';
import { PasswordService } from './password.service';
import { TokenService } from './token.service';

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  user: PublicUser;
}

export interface PublicUser { id: string; email: string | null; name: string }

export interface RequestInfo { ip: string; userAgent: string | null }

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_FAILS_PER_EMAIL = 5;
const MAX_FAILS_PER_IP = 20;

const publicUser = (u: UserRow): PublicUser => ({ id: u.id, email: u.email, name: u.name });

export class AuthService {
  constructor(
    private readonly repo: AuthRepository,
    private readonly tokens: TokenService,
    private readonly passwords: PasswordService,
    private readonly config: AuthConfig,
    private readonly google: GoogleOAuth | null,
  ) {}

  get googleEnabled() { return this.google !== null; }

  async signUp(emailRaw: string, password: string, nameRaw: string, req: RequestInfo): Promise<SessionTokens> {
    const email = emailRaw.trim().toLowerCase();
    const name = nameRaw.trim().slice(0, 120);
    if (!EMAIL.test(email) || email.length > 254) throw new BadRequestException('Correo no válido');
    if (!PasswordService.isAcceptable(password)) {
      throw new BadRequestException('La contraseña debe tener entre 8 y 72 caracteres');
    }
    if (await this.repo.isEmailRevoked(email)) throw new ForbiddenException('Este correo no puede registrarse');
    const user = await this.repo.createPasswordUser(email, await this.passwords.hash(password), name);
    if (!user) throw new ConflictException('Ya existe una cuenta con ese correo. Ingresa o usa Google.');
    return this.open(user, 'password', req);
  }

  async login(emailRaw: string, password: string, req: RequestInfo): Promise<SessionTokens> {
    const email = emailRaw.trim().toLowerCase();
    const failures = await this.repo.recentFailures(email, req.ip);
    if (failures.byEmail >= MAX_FAILS_PER_EMAIL || failures.byIp >= MAX_FAILS_PER_IP) {
      throw new HttpException('Demasiados intentos. Espera unos minutos.', HttpStatus.TOO_MANY_REQUESTS);
    }
    const user = await this.repo.findUserByEmail(email);
    const ok = await this.passwords.verify(password, user?.encrypted_password ?? null);
    await this.repo.recordAttempt(email, req.ip, ok);
    if (!user || !ok) throw new UnauthorizedException('Correo o contraseña incorrectos');
    if (await this.repo.isAdmin(user.id)) {
      throw new ForbiddenException('La administración ingresa solo con Google');
    }
    return this.open(user, 'password', req);
  }

  async loginWithGoogle(code: string, verifier: string, redirectUri: string, req: RequestInfo): Promise<SessionTokens> {
    if (!this.google) throw new ServiceUnavailableException('Google no está configurado');
    if (!this.redirectAllowed(redirectUri)) throw new BadRequestException('Dirección de retorno no permitida');
    let profile;
    try {
      profile = await this.google.exchange(code, verifier, redirectUri);
    } catch (error) {
      if (error instanceof GoogleRejected) throw new UnauthorizedException('Google rechazó el ingreso');
      throw new ServiceUnavailableException('No se pudo contactar a Google');
    }
    if (!profile.emailVerified) throw new UnauthorizedException('El correo de Google no está verificado');
    if (await this.repo.isEmailRevoked(profile.email)) throw new ForbiddenException('Este correo no puede ingresar');
    const user = await this.repo.upsertGoogleUser(profile.sub, profile.email, profile.name);
    return this.open(user, 'oauth', req);
  }

  async refresh(refreshToken: string): Promise<SessionTokens> {
    const next = this.tokens.newRefreshToken();
    const session = await this.repo.rotateRefresh(TokenService.hash(refreshToken), next.hash, next.expiresAt);
    if (!session) throw new UnauthorizedException();
    const user = await this.repo.findUserById(session.user_id);
    if (!user) throw new UnauthorizedException();
    return this.issue(user, session.id, session.auth_method, next.token);
  }

  /** Valida un token de acceso: firma, vencimiento y que la sesión siga abierta. Devuelve el id de usuario. */
  async verify(accessToken: string): Promise<{ userId: string; sessionId: string } | null> {
    const claims = await this.tokens.verifyAccess(accessToken);
    if (!claims) return null;
    if (!(await this.repo.sessionIsActive(claims.sessionId, claims.userId))) return null;
    return { userId: claims.userId, sessionId: claims.sessionId };
  }

  async me(userId: string): Promise<PublicUser> {
    const user = await this.repo.findUserById(userId);
    if (!user) throw new UnauthorizedException();
    return publicUser(user);
  }

  async logout(sessionId: string) {
    await this.repo.deleteSession(sessionId);
  }

  async changePassword(userId: string, sessionId: string, current: string, next: string) {
    if (!PasswordService.isAcceptable(next)) {
      throw new BadRequestException('La contraseña debe tener entre 8 y 72 caracteres');
    }
    const user = await this.repo.findUserById(userId);
    if (!user) throw new UnauthorizedException();
    if (user.encrypted_password && !(await this.passwords.verify(current, user.encrypted_password))) {
      throw new ForbiddenException('La contraseña actual no es correcta');
    }
    await this.repo.setPassword(userId, await this.passwords.hash(next));
    await this.repo.deleteOtherSessions(userId, sessionId);
  }

  /** Solo se aceptan retornos hacia el sitio propio (o localhost fuera de producción). */
  private redirectAllowed(uri: string) {
    if (!URL.canParse(uri)) return false;
    const url = new URL(uri);
    if (url.origin === this.config.siteUrl) return true;
    return process.env.NODE_ENV !== 'production' && ['localhost', '127.0.0.1'].includes(url.hostname);
  }

  private async open(user: UserRow, method: 'password' | 'oauth', req: RequestInfo) {
    const refresh = this.tokens.newRefreshToken();
    const sessionId = await this.repo.createSession(user.id, method, req.userAgent, refresh.hash, refresh.expiresAt);
    return this.issue(user, sessionId, method, refresh.token);
  }

  private async issue(user: UserRow, sessionId: string, method: 'password' | 'oauth', refreshToken: string) {
    const access = await this.tokens.signAccess({ userId: user.id, email: user.email, sessionId, method });
    return { accessToken: access.token, refreshToken, expiresAt: access.expiresAt, user: publicUser(user) };
  }
}
