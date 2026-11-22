import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  try {
    const { data, error } = await createSessionClient(context).auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: new URL('/auth/callback', siteUrl()).href, queryParams: { prompt: 'select_account' } },
    });
    if (!error && data.url) return context.redirect(data.url, 303);
  } catch {
    return context.redirect('/ingresar?estado=servicio', 303);
  }

  return context.redirect('/ingresar?estado=oauth', 303);
};
