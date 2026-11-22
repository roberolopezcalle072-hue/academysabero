import { apiRequest } from '../../../shared/infrastructure/api-request';

export interface Complaint {
  id: string; code: string; kind: 'reclamo' | 'queja'; full_name: string; doc_type: string; doc_number: string;
  address: string; phone: string; email: string; is_minor: boolean; guardian_name: string | null;
  service: string; amount_claimed: string | null; detail: string; request: string;
  status: 'open' | 'answered'; response: string | null; answered_at: string | null; created_at: string;
}

export async function loadComplaints(token: string, status: string, page: number) {
  try {
    const response = await apiRequest(`/admin/complaints?status=${status}&page=${page}`, token);
    return response.ok ? await response.json() as { complaints: Complaint[]; hasNext: boolean } : null;
  } catch {
    return null;
  }
}

export function answerComplaint(token: string, id: string, response: string) {
  return apiRequest(`/admin/complaints/${id}/answer`, token, { response });
}
