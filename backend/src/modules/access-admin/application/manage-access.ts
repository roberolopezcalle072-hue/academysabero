import { createHash, randomBytes } from 'node:crypto';

export interface AccessAdministration {
  list(token: string, page: number): Promise<unknown>;
  setEmail(token: string, email: string, active: boolean): Promise<void>;
  assign(token: string, email: string, course: string, digest: string | null): Promise<void>;
}

export class ManageAccess {
  constructor(private readonly storage: AccessAdministration) {}

  list(token: string, page: number) {
    return this.storage.list(token, page);
  }

  setEmail(token: string, email: string, active: boolean) {
    return this.storage.setEmail(token, email, active);
  }

  async assign(token: string, email: string, course: string, requireCode: boolean) {
    const code = requireCode ? randomBytes(32).toString('base64url') : null;
    const digest = code ? createHash('sha256').update(code).digest('hex') : null;
    await this.storage.assign(token, email, course, digest);
    return { code };
  }
}
