import { apiRequest } from '../../shared/infrastructure/api-request';

export interface Receipt {
  payment_id: string; receipt_number: number | null; paid_at: string; amount: number; currency: string;
  provider: string; external_id: string | null; course_name: string; full_name: string; email: string; phone: string; country: string;
}

export interface MyPayment {
  payment_id: string; receipt_number: number | null; status: string; amount: number; currency: string;
  course_name: string; created_at: string; paid_at: string | null;
}

export async function loadReceipt(token: string, id: string): Promise<Receipt | null> {
  try {
    const response = await apiRequest(`/payments/${encodeURIComponent(id)}/receipt`, token);
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

export async function loadMyPayments(token: string): Promise<MyPayment[]> {
  try {
    const response = await apiRequest('/payments/mine', token);
    return response.ok ? await response.json() : [];
  } catch {
    return [];
  }
}
