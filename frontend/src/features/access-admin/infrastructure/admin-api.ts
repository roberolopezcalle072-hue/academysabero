import { apiRequest } from '../../../shared/infrastructure/api-request';

interface Dashboard {
  students: { user_id: string; full_name: string; google_email: string; access_active: boolean }[];
  emails: { email: string; active: boolean }[];
  courses: { id: string; name: string }[];
  assignments: { email: string; course_id: string; claimed_at: string | null }[];
  hasNext: boolean;
}

export async function readDashboard(token: string, page: number): Promise<Dashboard> {
  const response = await apiRequest(`/admin/access?page=${page}`, token);
  if (!response.ok) throw new Error('Access administration is unavailable');
  return response.json();
}

export function submitAccessChange(token: string, form: FormData) {
  const action = form.get('action');
  const email = form.get('email');
  if (action === 'authorize' || action === 'revoke') {
    return apiRequest('/admin/access/emails', token, { email, active: action === 'authorize' });
  }
  if (action === 'assign') {
    return apiRequest('/admin/access/assignments', token, {
      email, courseId: form.get('courseId'), requireCode: form.get('requireCode') === 'on',
    });
  }
  return Promise.resolve(new Response(null, { status: 400 }));
}

export interface StudentRow { user_id: string; full_name: string; google_email: string; access_active: boolean; registered_at: string }

export async function readStudents(token: string, query: string, page: number) {
  try {
    const response = await apiRequest(`/admin/access/students?q=${encodeURIComponent(query)}&page=${page}`, token);
    return response.ok ? await response.json() as { students: StudentRow[]; hasNext: boolean } : null;
  } catch {
    return null;
  }
}

export function resetStudentPassword(token: string, id: string) {
  return apiRequest(`/admin/access/students/${id}/password`, token, {});
}
