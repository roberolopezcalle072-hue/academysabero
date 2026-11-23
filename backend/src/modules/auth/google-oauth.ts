import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

type Fetch = typeof fetch;

export interface GoogleProfile {
  sub: string;
  email: string;
  emailVerified: boolean;
  name: string;
}

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

/**
 * Inicio de sesión con Google directo (OAuth 2.0 + PKCE), sin intermediarios.
 * El navegador va a Google y vuelve con un "code"; aquí se cambia por un id_token firmado por Google,
 * se verifica su firma, emisor y destinatario, y se leen los datos del perfil.
 */
export class GoogleOAuth {
  constructor(
    private readonly clientId: string,
    private readonly clientSecret: string,
    private readonly http: Fetch = fetch,
    private readonly keys: JWTVerifyGetKey = createRemoteJWKSet(new URL(JWKS_URL)),
  ) {}

  get id() { return this.clientId; }

  async exchange(code: string, codeVerifier: string, redirectUri: string): Promise<GoogleProfile> {
    const response = await this.http(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code, code_verifier: codeVerifier, redirect_uri: redirectUri,
        client_id: this.clientId, client_secret: this.clientSecret, grant_type: 'authorization_code',
      }),
      signal: AbortSignal.timeout(10_000),
    });
    const body = await response.json().catch(() => ({})) as { id_token?: string };
    if (!response.ok || !body.id_token) throw new GoogleRejected();

    const { payload } = await jwtVerify(body.id_token, this.keys, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: this.clientId,
      algorithms: ['RS256'],
    }).catch(() => { throw new GoogleRejected(); });

    if (typeof payload.sub !== 'string' || typeof payload.email !== 'string') throw new GoogleRejected();
    return {
      sub: payload.sub,
      email: payload.email.trim().toLowerCase(),
      emailVerified: payload.email_verified === true || payload.email_verified === 'true',
      name: typeof payload.name === 'string' ? payload.name : '',
    };
  }
}

export class GoogleRejected extends Error {
  constructor() { super('Google rejected the sign-in'); }
}
