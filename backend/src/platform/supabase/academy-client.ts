import { createClient } from '@supabase/supabase-js';

export function createAcademyClient(url: string, key: string, token?: string) {
  if (!URL.canParse(url)) throw new Error('Invalid SUPABASE_URL');
  const endpoint = new URL(url);
  if (!['http:', 'https:'].includes(endpoint.protocol) || endpoint.username || endpoint.password) {
    throw new Error('SUPABASE_URL must be an HTTP endpoint without credentials');
  }
  if (process.env.NODE_ENV === 'production' && endpoint.protocol !== 'https:') {
    throw new Error('SUPABASE_URL must use HTTPS in production');
  }
  if (key.startsWith('sb_secret_') || jwtRole(key) === 'service_role') {
    throw new Error('SUPABASE_PUBLISHABLE_KEY must be public');
  }

  return createClient(endpoint.href, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    ...(token ? { accessToken: async () => token } : {}),
    global: {
      fetch: (input, init) => {
        const timeout = AbortSignal.timeout(4_000);
        const inherited = init?.signal ?? (input instanceof Request ? input.signal : null);
        const signal = inherited ? AbortSignal.any([inherited, timeout]) : timeout;
        return fetch(input, { ...init, signal });
      },
    },
  });
}

function jwtRole(key: string): unknown {
  const segments = key.split('.');
  if (segments.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(segments[1], 'base64url').toString('utf8')).role;
  } catch {
    return null;
  }
}
