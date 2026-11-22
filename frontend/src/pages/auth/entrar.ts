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
  const password = String(form.get('password') ?? '');
  if (!EMAIL.test(email) || email.length > 254 || password.length < 1 || password.length > 200) {
    return context.redirect('/ingresar?estado=credenciales', 303);
  }

  try {
    const { error } = await createSessionClient(context).auth.signInWithPassword({ email, password });
    if (!error) return context.redirect('/campus', 303);
    if (error.code === 'email_not_confirmed') return context.redirect('/ingresar?estado=confirmar', 303);
    if (error.status === 400 || error.status === 401) return context.redirect('/ingresar?estado=credenciales', 303);
  } catch {
    return context.redirect('/ingresar?estado=servicio', 303);
  }
  return context.redirect('/ingresar?estado=servicio', 303);
};
