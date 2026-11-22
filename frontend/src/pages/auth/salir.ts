import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  try {
    const { error } = await createSessionClient(context).auth.signOut({ scope: 'local' });
    if (error) return context.redirect('/ingresar?estado=servicio', 303);
    return context.redirect('/ingresar', 303);
  } catch {
    return context.redirect('/ingresar?estado=servicio', 303);
  }
};
