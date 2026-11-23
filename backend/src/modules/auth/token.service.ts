import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import type { AuthConfig } from './auth.config';

export const ISSUER = 'sabero-academy';
export const AUDIENCE = 'authenticated';

export interface AccessClaims {
  userId: string;
  email: string | null;
  sessionId: string;
  method: 'password' | 'oauth';
}

/** Firma y verifica los tokens de acceso (JWT HS256). El mismo formato lo entiende la capa de datos (RLS). */
export class TokenService {
  constructor(private readonly config: AuthConfig) {}

  async signAccess(claims: AccessClaims) {
    const now = Math.floor(Date.now() / 1000);
    const exp = now + this.config.accessTtl;
    const token = await new SignJWT({
      role: 'authenticated',
      email: claims.email,
      session_id: claims.sessionId,
      amr: [{ method: claims.method, timestamp: now }],
    })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuer(ISSUER).setAudience(AUDIENCE).setSubject(claims.userId)
      .setIssuedAt(now).setExpirationTime(exp)
      .sign(this.config.jwtSecret);
    return { token, expiresAt: exp, expiresIn: this.config.accessTtl };
  }

  /** Devuelve los datos del token o null si es inválido, falso o vencido. No consulta la base de datos. */
  async verifyAccess(token: string): Promise<AccessClaims | null> {
    try {
      const { payload } = await jwtVerify(token, this.config.jwtSecret, {
        algorithms: ['HS256'], issuer: ISSUER, audience: AUDIENCE,
      });
      const amr = Array.isArray(payload.amr) ? payload.amr as { method?: string }[] : [];
      const sessionId = typeof payload.session_id === 'string' ? payload.session_id : '';
      if (!payload.sub || !sessionId) return null;
      return {
        userId: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : null,
        sessionId,
        method: amr[0]?.method === 'oauth' ? 'oauth' : 'password',
      };
    } catch {
      return null;
    }
  }

  /** Token de refresco opaco: se entrega una sola vez y en la base solo se guarda su resumen. */
  newRefreshToken() {
    const token = randomBytes(32).toString('base64url');
    return { token, hash: TokenService.hash(token), expiresAt: new Date(Date.now() + this.config.refreshTtl * 1000) };
  }

  static hash(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }
}
