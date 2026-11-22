import type { APIRoute } from 'astro';
import { apiRequest } from '../../shared/infrastructure/api-request';
import { siteUrl } from '../../shared/config/server';

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) return new Response(null, { status: 403 });
  const form = await context.request.formData();
  // Campo trampa para bots: un humano lo deja vacío.
  if (String(form.get('website') ?? '') !== '') return context.redirect('/libro-de-reclamaciones?estado=servicio', 303);
  const get = (key: string) => String(form.get(key) ?? '');

  try {
    const response = await apiRequest('/complaints', undefined, {
      kind: get('kind'), fullName: get('fullName'), docType: get('docType'), docNumber: get('docNumber'),
      address: get('address'), phone: get('phone'), email: get('email'), isMinor: form.get('isMinor') === 'on',
      guardian: get('guardian'), service: get('service'), amount: get('amount'), detail: get('detail'),
      request: get('request'), acceptTruth: form.get('acceptTruth') === 'on',
    }, 15000);
    if (response.status === 201) {
      const { code } = await response.json();
      return context.redirect(`/libro-de-reclamaciones/gracias?codigo=${encodeURIComponent(String(code))}&tipo=${encodeURIComponent(get('kind'))}`, 303);
    }
    if (response.status === 429) return context.redirect('/libro-de-reclamaciones?estado=limite', 303);
    if (response.status === 400) return context.redirect('/libro-de-reclamaciones?estado=datos', 303);
  } catch {
    return context.redirect('/libro-de-reclamaciones?estado=servicio', 303);
  }
  return context.redirect('/libro-de-reclamaciones?estado=servicio', 303);
};
