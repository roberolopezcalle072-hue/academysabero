import type { APIRoute } from 'astro';
import { apiRequest } from '../../../shared/infrastructure/api-request';
import { siteUrl } from '../../../shared/config/server';

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) return new Response(null, { status: 403 });
  const token = context.locals.accessToken;
  if (!token) return json({ reason: 'login' }, 401);

  let body: Record<string, unknown>;
  try { body = await context.request.json(); } catch { return json({ reason: 'bad-request' }, 400); }

  try {
    const response = await apiRequest('/payments/start', token, {
      courseId: body.courseId, fullName: body.fullName, phone: body.phone, country: body.country,
      notes: body.notes, slot: body.slot ?? undefined, acceptTerms: body.acceptTerms === true,
    }, 15000);
    return json(await response.json().catch(() => ({})), response.status);
  } catch {
    return json({ reason: 'unavailable' }, 503);
  }
};
