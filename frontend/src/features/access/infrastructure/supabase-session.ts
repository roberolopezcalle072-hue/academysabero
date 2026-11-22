import { createServerClient, parseCookieHeader } from '@supabase/ssr';
import type { APIContext } from 'astro';
import { publicSupabaseConfig, siteUrl } from '../../../shared/config/server';

export function createSessionClient({ request, cookies }: Pick<APIContext, 'request' | 'cookies'>) {
  const secure = siteUrl().protocol === 'https:';
  const { url, key } = publicSupabaseConfig();
  return createServerClient(url, key, {
    global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(4000) }) },
    cookieOptions: { path: '/', httpOnly: true, sameSite: 'lax', secure },
    cookies: {
      getAll: () => parseCookieHeader(request.headers.get('cookie') ?? '').flatMap(({ name, value }) =>
        value === undefined ? [] : [{ name, value }],
      ),
      setAll: (updates) => {
        for (const { name, value, options } of updates) {
          cookies.set(name, value, { ...options, httpOnly: true, sameSite: 'lax', secure });
        }
      },
    },
  });
}
