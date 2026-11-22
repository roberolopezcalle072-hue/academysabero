import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  const form = await context.request.formData();
  const password = String(form.get('password') ?? '');
  const confirm = String(form.get('confirm') ?? '');
  if (password.length < 8 || password.length > 72) return context.redirect('/nueva-clave?estado=clave', 303);
  if (password !== confirm) return context.redirect('/nueva-clave?estado=distintas', 303);

  try {
    const client = createSessionClient(context);
    const { data } = await client.auth.getSession();
    if (!data.session) return context.redirect('/recuperar?estado=expirado', 303);
    const { error } = await client.auth.updateUser({ password });
    if (error) {
      if (error.code === 'same_password') return context.redirect('/nueva-clave?estado=igual', 303);
      if (error.code === 'weak_password') return context.redirect('/nueva-clave?estado=clave', 303);
      return context.redirect('/nueva-clave?estado=servicio', 303);
    }
    context.cookies.delete('academy_recovery', { path: '/' });
    return context.redirect('/campus?estado=clave-cambiada', 303);
  } catch {
    return context.redirect('/nueva-clave?estado=servicio', 303);
  }
};
