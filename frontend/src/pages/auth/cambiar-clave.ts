import type { APIRoute } from 'astro';
import { createSessionClient } from '../../features/access/infrastructure/supabase-session';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  const form = await context.request.formData();
  const current = String(form.get('current') ?? '');
  const password = String(form.get('password') ?? '');
  const confirm = String(form.get('confirm') ?? '');
  const back = (estado: string) => context.redirect(`/cuenta/perfil?estado=${estado}`, 303);

  if (password.length < 8 || password.length > 72) return back('clave');
  if (password !== confirm) return back('distintas');

  try {
    const client = createSessionClient(context);
    const { data: { user } } = await client.auth.getUser();
    if (!user?.email) return context.redirect('/ingresar', 303);

    // Si la cuenta ya tiene contraseña, se exige la actual (protege una sesión abierta en un equipo ajeno).
    const hasPassword = user.identities?.some((identity) => identity.provider === 'email') ?? false;
    if (hasPassword) {
      if (!current) return back('actual');
      const { error } = await client.auth.signInWithPassword({ email: user.email, password: current });
      if (error) return error.status === 400 || error.status === 401 ? back('actual') : back('servicio');
      if (current === password) return back('igual');
    }

    const { error } = await client.auth.updateUser({ password });
    if (error) {
      if (error.code === 'same_password') return back('igual');
      if (error.code === 'weak_password') return back('clave');
      return back('servicio');
    }
    return back('ok');
  } catch {
    return back('servicio');
  }
};
