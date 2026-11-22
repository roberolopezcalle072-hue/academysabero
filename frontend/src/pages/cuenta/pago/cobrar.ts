import type { APIRoute } from 'astro';
import { apiRequest } from '../../../shared/infrastructure/api-request';
import { siteUrl } from '../../../shared/config/server';

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) return new Response(null, { status: 403 });
  const token = context.locals.accessToken;
  if (!token) return json({ reason: 'login' }, 401);

  let body: Record<string, unknown>;
  try { body = await context.request.json(); } catch { return json({ reason: 'bad-request' }, 400); }
  const paymentId = String(body.paymentId ?? '');
  if (!UUID.test(paymentId) || typeof body.token !== 'string') return json({ reason: 'bad-request' }, 400);

  try {
    // El cobro con la pasarela puede tardar unos segundos.
    const response = await apiRequest(`/payments/${paymentId}/charge`, token, { token: body.token }, 30000);
    return json(await response.json().catch(() => ({})), response.status);
  } catch {
    return json({ reason: 'unavailable' }, 503);
  }
};
