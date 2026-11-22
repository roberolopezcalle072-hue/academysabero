import type { APIContext } from 'astro';
import { createSessionClient } from './supabase-session';

export async function readSessionToken(context: Pick<APIContext, 'cookies' | 'request'>) {
  const { data, error } = await createSessionClient(context).auth.getSession();
  if (error && error.name !== 'AuthSessionMissingError' &&
      error.code !== 'refresh_token_not_found' && error.code !== 'refresh_token_already_used') {
    throw error;
  }
  return data.session?.access_token ?? null;
}
