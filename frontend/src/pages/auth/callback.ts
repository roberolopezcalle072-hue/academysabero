import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';

export const GET: APIRoute = async (context) => {
  const code = context.url.searchParams.get('code');
  let destination = '/ingresar?estado=oauth';

  if (code) {
    try {
      const client = createSessionClient(context);
      const { error } = await client.auth.exchangeCodeForSession(code);
      if (!error) {
        destination = '/campus';
        const methods = await sessionMethods(client);
        const flagged = context.cookies.get('academy_recovery')?.value === '1';
        // Enlace de recuperación: pedir la nueva contraseña (la marca solo cuenta si no fue un ingreso con Google).
        if (methods.includes('recovery') || (flagged && !methods.includes('oauth'))) destination = '/nueva-clave';
        context.cookies.delete('academy_recovery', { path: '/' });
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

async function sessionMethods(client: ReturnType<typeof createSessionClient>): Promise<string[]> {
  try {
    const { data } = await client.auth.getSession();
    const payload = data.session?.access_token.split('.')[1];
    if (!payload) return [];
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return Array.isArray(claims.amr) ? claims.amr.map((a: { method?: string }) => String(a.method)) : [];
  } catch {
    return [];
  }
}
