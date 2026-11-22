import { apiRequest } from '../../../shared/infrastructure/api-request';

export interface CatalogCourse {
  id: string;
  name: string;
  description: string;
  image_path: string;
  price_regular: number;
  price_offer: number;
  currency: string;
  price_regular_pen: number | null;
  price_offer_pen: number | null;
  enrolled: boolean;
  request_status: 'pending' | 'approved' | 'rejected' | null;
}

export interface AdminRequest {
  id: string;
  full_name: string;
  email: string;
  phone: string;
  country: string;
  notes: string | null;
  price_regular: number;
  price_offer: number;
  currency: string;
  terms_version: string;
  terms_accepted_at: string;
  status: 'pending' | 'approved' | 'rejected';
  review_note: string | null;
  created_at: string;
  reviewed_at: string | null;
  academy_courses: { name: string } | null;
}

export async function loadCatalog(token: string): Promise<CatalogCourse[] | null> {
  try {
    const response = await apiRequest('/catalog', token);
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

export function sendRequest(token: string, body: Record<string, unknown>) {
  return apiRequest('/enrollment-requests', token, body);
}

export async function loadAdminRequests(token: string, status: string, page: number) {
  try {
    const response = await apiRequest(`/admin/enrollment-requests?status=${status}&page=${page}`, token);
    return response.ok ? await response.json() as { requests: AdminRequest[]; hasNext: boolean } : null;
  } catch {
    return null;
  }
}

export function decideRequest(token: string, id: string, approve: boolean, note: string | null) {
  return apiRequest(`/admin/enrollment-requests/${id}/decision`, token, { approve, note });
}

export interface PaymentsConfig { enabled: boolean; provider?: string; [key: string]: unknown }

/** Indica si el pago en línea está activo (hay una pasarela configurada en el backend). */
export async function loadPaymentsConfig(): Promise<PaymentsConfig> {
  try {
    const response = await apiRequest('/payments/config');
    return response.ok ? await response.json() : { enabled: false };
  } catch {
    return { enabled: false };
  }
}

export interface PublicPrice {
  name: string; price_regular: number | null; price_offer: number | null; currency: string;
  price_regular_pen: number | null; price_offer_pen: number | null;
}

/** Precios públicos para la portada. Devuelve null si el backend no responde (se usan los valores de respaldo). */
export async function loadPublicPrices(): Promise<PublicPrice | null> {
  try {
    const response = await apiRequest('/catalog/public');
    if (!response.ok) return null;
    const list = await response.json() as PublicPrice[];
    return list[0] ?? null;
  } catch {
    return null;
  }
}
