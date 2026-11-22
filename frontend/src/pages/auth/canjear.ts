import type { APIRoute } from 'astro';
import { readSessionToken } from '../../features/access/infrastructure/read-session-token';
import { apiRequest } from '../../shared/infrastructure/api-request';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }

  try {
    const token = await readSessionToken(context);
    if (!token) return context.redirect('/ingresar', 303);
    const code = (await context.request.formData()).get('code');
    if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{32,128}$/.test(code.trim())) {
      return context.redirect('/ingresar?estado=codigo', 303);
    }
    const response = await apiRequest('/access/redeem', token, { code: code.trim() });
    if (response.ok) return context.redirect('/campus', 303);
    if (response.status === 401) return context.redirect('/ingresar', 303);
    if (response.status === 403) return context.redirect('/ingresar?estado=codigo', 303);
  } catch {
    return context.redirect('/ingresar?estado=servicio', 303);
  }

  return context.redirect('/ingresar?estado=servicio', 303);
};
