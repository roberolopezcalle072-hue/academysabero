import { apiRequest } from '../../../shared/infrastructure/api-request';

export interface AdminSummary {
  students: number;
  pending_requests: number;
  open_inquiries: number;
  open_complaints: number;
  paid_count: number;
  revenue: { currency: string; total: number }[];
  payments: {
    id: string; status: 'paid' | 'refunded'; amount: number; currency: string;
    course: string; student: string; email: string; date: string;
  }[];
}

export async function loadSummary(token: string): Promise<AdminSummary | null> {
  try {
    const response = await apiRequest('/admin/summary', token);
    return response.ok ? await response.json() as AdminSummary : null;
  } catch {
    return null;
  }
}
