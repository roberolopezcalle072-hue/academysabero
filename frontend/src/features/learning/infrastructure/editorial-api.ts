import { apiRequest } from '../../../shared/infrastructure/api-request';
import type { FormValues } from '../presentation/editorial-fields';

interface Row extends FormValues { id: string; status: string }
interface Catalog {
  courses: (Row & { name: string })[];
  program: FormValues | null;
  course: (Row & { name: string }) | null;
  modules: (Row & { title: string })[];
  lessons: (Row & { module_id: string; title: string })[];
  materials: (FormValues & { id: string; lesson_id: string; title: string })[];
  hasNext: boolean;
}

export async function loadCatalog(token: string, page: number, course: string) {
  const query = new URLSearchParams({ page: String(page) });
  if (course) query.set('course', course);
  const response = await apiRequest(`/admin/learning?${query}`, token);
  if (!response.ok) return null;
  return await response.json() as Catalog;
}

export function saveEditorial(token: string, form: FormData) {
  const entity = form.get('entity');
  if (typeof entity !== 'string' || !['program', 'course', 'module', 'lesson', 'material'].includes(entity)) {
    return Promise.resolve(new Response(null, { status: 400 }));
  }
  const fields = Object.fromEntries(form);
  if (entity === 'program') fields.published = form.has('published') ? 'true' : 'false';
  return apiRequest(`/admin/learning/${entity}`, token, fields);
}
