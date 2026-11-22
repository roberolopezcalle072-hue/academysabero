import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';

export const GET: APIRoute = async (context) => {
  const code = context.url.searchParams.get('code');
  let destination = '/ingresar?estado=oauth';

  if (code) {
    try {
      const { error } = await createSessionClient(context).auth.exchangeCodeForSession(code);
      if (!error) {
        destination = '/campus';
      }
    } catch {
      destination = '/ingresar?estado=servicio';
    }
  }

  const response = context.redirect(destination, 303);
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('Referrer-Policy', 'no-referrer');
  return response;
};
