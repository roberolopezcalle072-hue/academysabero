import type { Campus, Course, InquiryPage, Program } from '../domain/content';
import { apiRequest } from '../../../shared/infrastructure/api-request';

export type ContentResult<T> = { status: 'ok'; value: T } | { status: 'missing' | 'unavailable' };

async function read<T>(path: string, token?: string): Promise<ContentResult<T>> {
  try {
    const response = await apiRequest(path, token);
    if (response.status === 404) return { status: 'missing' };
    if (!response.ok) return { status: 'unavailable' };
    return { status: 'ok', value: await response.json() as T };
  } catch {
    return { status: 'unavailable' };
  }
}

export const loadProgram = () => read<Program>('/program');
export const loadCampus = (token: string) => read<Campus>('/campus', token);
export const loadCourse = (token: string, id: string) => read<Course>(`/campus/courses/${encodeURIComponent(id)}`, token);
export const loadInquiries = (token: string, page: number) => read<InquiryPage>(`/campus/inquiries?page=${page}`, token);

export function completeLesson(token: string, id: string) {
  return apiRequest(`/campus/lessons/${encodeURIComponent(id)}/complete`, token, {});
}

export function sendInquiry(token: string, subject: string, body: string) {
  return apiRequest('/campus/inquiries', token, { subject, body });
}
