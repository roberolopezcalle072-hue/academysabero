export type AcademyRole = 'student' | 'admin';
export type AccessDecision = AcademyRole | 'denied' | 'enrollment-required';
export type AccessResult =
  | { status: 'invalid-session' | 'access-denied' | 'enrollment-required' }
  | { status: 'authorized'; member: { id: string; role: AcademyRole } };

export interface AcademyIdentity {
  verify(accessToken: string): Promise<string | null>;
  resolve(accessToken: string): Promise<AccessDecision>;
  redeem(accessToken: string, code: string): Promise<boolean>;
}

export class ResolveAccess {
  constructor(private readonly identity: AcademyIdentity) {}

  async execute(accessToken: string): Promise<AccessResult> {
    const id = await this.identity.verify(accessToken);
    if (!id) return { status: 'invalid-session' };

    const role = await this.identity.resolve(accessToken);
    if (role === 'denied') return { status: 'access-denied' };
    if (role === 'enrollment-required') return { status: role };

    return { status: 'authorized', member: { id, role } };
  }

  async redeem(accessToken: string, code: string): Promise<'invalid-session' | 'accepted' | 'rejected'> {
    if (!await this.identity.verify(accessToken)) return 'invalid-session';
    return await this.identity.redeem(accessToken, code) ? 'accepted' : 'rejected';
  }
}
