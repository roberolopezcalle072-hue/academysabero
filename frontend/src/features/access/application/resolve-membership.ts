import type { Membership } from '../domain/membership';

export type MembershipResult =
  | { status: 'guest' | 'denied' | 'unavailable' | 'enrollment-required' }
  | { status: 'authorized'; member: Membership };

export async function resolveMembership(
  readToken: () => Promise<string | null>,
  lookup: (token: string) => Promise<MembershipResult>,
): Promise<MembershipResult> {
  try {
    const token = await readToken();
    return token ? await lookup(token) : { status: 'guest' };
  } catch {
    return { status: 'unavailable' };
  }
}
