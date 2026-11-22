import { apiRequest } from '../../../shared/infrastructure/api-request';
import type { Administration, Agenda, Roster } from '../domain/session';

async function read<T>(path: string, token: string): Promise<T | null> {
  const response = await apiRequest(path, token).catch(() => null);
  if (!response?.ok) return null;
  return response.json().catch(() => null);
}

export const loadAgenda = (token: string, page: number) => read<Agenda>(`/campus/sessions?page=${page}`, token);

export function loadAdministration(token: string, page: number, selected: string) {
  const query = new URLSearchParams({ page: String(page) });
  if (selected) query.set('session', selected);
  return read<Administration>(`/admin/sessions?${query}`, token);
}

export function loadRoster(token: string, session: string, page: number, present: boolean) {
  return read<Roster>(`/admin/sessions/${session}/attendance?page=${page}&present=${present ? '1' : '0'}`, token);
}

export function submitSessionAction(token: string, form: FormData) {
  const action = form.get('action');
  const id = form.get('id');
  if (action === 'save') return apiRequest('/admin/sessions', token, Object.fromEntries(form));
  if (typeof id === 'string' && /^[\da-f-]{36}$/i.test(id)) {
    if (action === 'cancel') return apiRequest(`/admin/sessions/${id}/cancel`, token, {});
    if (action === 'attendance') {
      return apiRequest(`/admin/sessions/${id}/attendance`, token, {
        student: form.get('student'), status: form.get('status'),
      });
    }
  }
  return Promise.resolve(new Response(null, { status: 400 }));
}
