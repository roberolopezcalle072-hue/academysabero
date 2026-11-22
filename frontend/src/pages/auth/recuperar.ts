import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  const form = await context.request.formData();
  const email = String(form.get('email') ?? '').trim().toLowerCase();
  if (!EMAIL.test(email) || email.length > 254) return context.redirect('/recuperar?estado=datos', 303);

  try {
    // La respuesta es siempre la misma exista o no la cuenta, para no revelar qué correos están registrados.
    await createSessionClient(context).auth.resetPasswordForEmail(email, {
      redirectTo: new URL('/auth/callback', siteUrl()).href,
    });
    // Marca de corta vida: el callback sabe que debe pedir la nueva contraseña.
    context.cookies.set('academy_recovery', '1', {
      path: '/', httpOnly: true, sameSite: 'lax', secure: siteUrl().protocol === 'https:', maxAge: 60 * 60,
    });
    return context.redirect('/recuperar?estado=enviado', 303);
  } catch {
    return context.redirect('/recuperar?estado=servicio', 303);
  }
};
