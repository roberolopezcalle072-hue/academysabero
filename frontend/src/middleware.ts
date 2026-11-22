import { defineMiddleware } from 'astro:middleware';
import { resolveMembership } from './features/access/application/resolve-membership';
import { lookupMembership } from './features/access/infrastructure/academy-api';
import { readSessionToken } from './features/access/infrastructure/read-session-token';

export const onRequest = defineMiddleware(async (context, next) => {
  const path = context.url.pathname;
  const admin = path === '/admin' || path.startsWith('/admin/');
  const campus = path === '/campus' || path.startsWith('/campus/');
  // /cuenta: cualquier persona con sesión (aunque todavía no tenga cursos).
  const account = path === '/cuenta' || path.startsWith('/cuenta/');
  if (!admin && !campus && !account && !path.startsWith('/auth/')) return next();

  let response: Response;
  if (!admin && !campus && !account) {
    response = await next();
  } else {
    const access = await resolveMembership(() => readSessionToken(context), (token) => {
      context.locals.accessToken = token;
      return lookupMembership(token);
    });
    if (access.status === 'authorized') {
      context.locals.member = access.member;
      response = admin && access.member.role !== 'admin' ? context.redirect('/campus') : await next();
    } else if (access.status === 'enrollment-required' && account) {
      response = await next();
    } else {
      const location = {
        guest: '/ingresar',
        unavailable: '/ingresar?estado=servicio',
        denied: '/ingresar?estado=acceso',
        'enrollment-required': '/cuenta',
      }[access.status];
      response = context.redirect(location, 303);
    }
  }

  response.headers.set('Cache-Control', 'private, no-store');
  return response;
});
