import type { SupabaseClient } from '@supabase/supabase-js';
import { createAcademyClient } from '../../../platform/supabase/academy-client';
import type { AcademyIdentity, AccessDecision } from '../application/resolve-access';

export class SupabaseIdentity implements AcademyIdentity {
  private readonly authClient: SupabaseClient;

  constructor(private readonly url: string, private readonly key: string) {
    this.authClient = createAcademyClient(url, key);
  }

  async verify(accessToken: string): Promise<string | null> {
    const { data, error } = await this.authClient.auth.getUser(accessToken);
    if (error) {
      if (error.status === 400 || error.status === 401 || error.status === 403) return null;
      throw error;
    }
    return data.user?.id ?? null;
  }

  async resolve(accessToken: string): Promise<AccessDecision> {
    const { data, error } = await this.client(accessToken).rpc('academy_resolve_access');
    if (error) throw error;
    if (data === 'admin' || data === 'student' || data === 'denied' || data === 'enrollment-required') return data;
    throw new Error('Unexpected access decision from Supabase');
  }

  async redeem(accessToken: string, code: string): Promise<boolean> {
    const { data, error } = await this.client(accessToken).rpc('academy_redeem_access_code', { p_code: code });
    if (error) throw error;
    return data === true;
  }

  private client(accessToken: string) {
    return createAcademyClient(this.url, this.key, accessToken);
  }
}
