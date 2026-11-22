import type { APIRoute } from 'astro';
import { sendRequest } from '../../features/enrollment/infrastructure/enrollment-api';
import { siteUrl } from '../../shared/config/server';

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export const POST: APIRoute = async (context) => {
  if (context.request.headers.get('origin') !== siteUrl().origin) {
    return new Response(null, { status: 403 });
  }
  const token = context.locals.accessToken;
  if (!token) return context.redirect('/ingresar', 303);

  const form = await context.request.formData();
  const courseId = String(form.get('courseId') ?? '');
  if (!UUID.test(courseId)) return context.redirect('/cuenta/cursos', 303);
  const back = (estado: string) => context.redirect(`/cuenta/inscripcion/${courseId}?estado=${estado}`, 303);

  if (form.get('acceptTerms') !== 'on') return back('terminos');

  try {
    const response = await sendRequest(token, {
      courseId,
      fullName: String(form.get('fullName') ?? ''),
      phone: String(form.get('phone') ?? ''),
      country: String(form.get('country') === '__otro' ? form.get('countryOther') ?? '' : form.get('country') ?? ''),
      notes: String(form.get('notes') ?? ''),
      acceptTerms: true,
    });
    if (response.status === 201) return context.redirect('/cuenta?estado=solicitud-enviada', 303);
    if (response.status === 409) return context.redirect('/cuenta?estado=solicitud-existente', 303);
    if (response.status === 400) return back('datos');
    if (response.status === 401) return context.redirect('/ingresar', 303);
  } catch {
    return back('servicio');
  }
  return back('servicio');
};
