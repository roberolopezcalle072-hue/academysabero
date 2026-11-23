export interface AuthConfig {
  /** Secreto con el que se firman y verifican los tokens de acceso (mínimo 32 caracteres). */
  jwtSecret: Uint8Array;
  /** Segundos de vida del token de acceso. */
  accessTtl: number;
  /** Segundos de vida del token de refresco. */
  refreshTtl: number;
  /** Origen público del sitio (para validar la dirección de retorno de Google). */
  siteUrl: string;
  google: { clientId: string; clientSecret: string } | null;
}

export function loadAuthConfig(env: NodeJS.ProcessEnv = process.env): AuthConfig {
  const secret = env.JWT_SECRET?.trim() ?? '';
  if (secret.length < 32) throw new Error('JWT_SECRET must have at least 32 characters');

  const clientId = env.GOOGLE_CLIENT_ID?.trim();
  const clientSecret = env.GOOGLE_CLIENT_SECRET?.trim();
  if (Boolean(clientId) !== Boolean(clientSecret)) {
    throw new Error('Set both GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET, or neither');
  }

  return {
    jwtSecret: new TextEncoder().encode(secret),
    accessTtl: Number(env.ACCESS_TOKEN_TTL ?? 3600),
    refreshTtl: Number(env.REFRESH_TOKEN_TTL ?? 60 * 60 * 24 * 30),
    siteUrl: (env.SITE_URL?.trim() || 'https://academy.saberoconsulting.com').replace(/\/+$/, ''),
    google: clientId && clientSecret ? { clientId, clientSecret } : null,
  };
}
