import { requiredEnv } from '../config/server';

export function apiRequest(path: string, token?: string, body?: object) {
  const base = requiredEnv('API_BASE_URL').replace(/\/+$/, '');
  const headers = new Headers();
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (body) headers.set('Content-Type', 'application/json');
  return fetch(`${base}${path}`, {
    method: body ? 'POST' : 'GET',
    headers,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(5000),
    redirect: 'error',
  });
}
