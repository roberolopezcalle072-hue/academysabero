import { apiRequest } from '../../../shared/infrastructure/api-request';

export interface AdminInquiry {
  id: string;
  subject: string;
  body: string;
  status: 'open' | 'answered' | 'closed';
  created_at: string;
  student_name: string;
  student_email: string;
  replies: { id: string; body: string; created_at: string }[];
}

export async function loadInquiries(token: string, status: string, page: number) {
  try {
    const response = await apiRequest(`/admin/inquiries?status=${status}&page=${page}`, token);
    return response.ok ? await response.json() as { items: AdminInquiry[]; hasNext: boolean } : null;
  } catch {
    return null;
  }
}

export function replyInquiry(token: string, id: string, body: string) {
  return apiRequest(`/admin/inquiries/${id}/reply`, token, { body });
}
