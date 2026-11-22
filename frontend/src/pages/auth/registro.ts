import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  const form = await context.request.formData();
  const name = String(form.get('name') ?? '').trim().replace(/\s+/g, ' ');
  const email = String(form.get('email') ?? '').trim().toLowerCase();
  const password = String(form.get('password') ?? '');
  const accepted = form.get('accept') === 'on';

  if (name.length < 2 || name.length > 120 || !EMAIL.test(email) || email.length > 254) {
    return context.redirect('/registro?estado=datos', 303);
  }
  if (password.length < 8 || password.length > 72) return context.redirect('/registro?estado=clave', 303);
  if (!accepted) return context.redirect('/registro?estado=terminos', 303);

  try {
    const { data, error } = await createSessionClient(context).auth.signUp({
      email,
      password,
      options: {
        data: { full_name: name },
        emailRedirectTo: new URL('/auth/callback', siteUrl()).href,
      },
    });
    if (error) {
      if (error.code === 'weak_password') return context.redirect('/registro?estado=clave', 303);
      if (error.status === 403) return context.redirect('/registro?estado=bloqueado', 303);
      return context.redirect('/registro?estado=servicio', 303);
    }
    // Con la confirmación por correo desactivada, la sesión se abre al instante.
    if (data.session) return context.redirect('/cuenta', 303);
    return context.redirect('/registro?estado=revisa-correo', 303);
  } catch {
    return context.redirect('/registro?estado=servicio', 303);
  }
};
