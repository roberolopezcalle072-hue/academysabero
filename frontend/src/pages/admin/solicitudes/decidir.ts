import type { APIRoute } from 'astro';
import { decideRequest } from '../../../features/enrollment/infrastructure/enrollment-api';
import { siteUrl } from '../../../shared/config/server';

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }
  const token = context.locals.accessToken;
  if (!token || context.locals.member?.role !== 'admin') return context.redirect('/ingresar', 303);

  const form = await context.request.formData();
  const id = String(form.get('id') ?? '');
  const decision = form.get('decision');
  const estado = ['pending', 'approved', 'rejected', 'all'].includes(String(form.get('estado'))) ? String(form.get('estado')) : 'pending';
  const done = (ok: boolean) => context.redirect(`/admin/solicitudes?estado=${estado}&guardado=${ok ? 1 : 0}`, 303);
  if (!UUID.test(id) || (decision !== 'approve' && decision !== 'reject')) return done(false);

  try {
    const note = String(form.get('note') ?? '').trim();
    const response = await decideRequest(token, id, decision === 'approve', note || null);
    return done(response.ok);
  } catch {
    return done(false);
  }
};
