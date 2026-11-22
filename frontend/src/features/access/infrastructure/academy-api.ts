import type { MembershipResult } from '../application/resolve-membership';
import { apiRequest } from '../../../shared/infrastructure/api-request';

export async function lookupMembership(token: string): Promise<MembershipResult> {
  const response = await apiRequest('/access/me', token);
  if (response.status === 401) return { status: 'guest' };
  if (response.status === 403) {
    const { reason } = await response.json();
    return { status: reason === 'enrollment-required' ? 'enrollment-required' : 'denied' };
  }
  if (!response.ok) return { status: 'unavailable' };

  const { id, role } = await response.json();
  if (typeof id !== 'string' || (role !== 'student' && role !== 'admin')) {
    return { status: 'unavailable' };
  }
  return { status: 'authorized', member: { id, role } };
}
