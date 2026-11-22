import { createHash, randomBytes, randomInt } from 'node:crypto';

export interface AccessAdministration {
  list(token: string, page: number): Promise<unknown>;
  setEmail(token: string, email: string, active: boolean): Promise<void>;
  assign(token: string, email: string, course: string, digest: string | null): Promise<void>;
  students(token: string, query: string, page: number): Promise<unknown>;
  setPassword(token: string, student: string, password: string): Promise<void>;
}

// Sin caracteres ambiguos (0/O, 1/l/I) para que sea fácil de dictar o leer.
const PASSWORD_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

export function generatePassword(length = 14): string {
  return Array.from({ length }, () => PASSWORD_ALPHABET[randomInt(PASSWORD_ALPHABET.length)]).join('');
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

  students(token: string, query: string, page: number) {
    return this.storage.students(token, query, page);
  }

  async resetPassword(token: string, student: string) {
    const password = generatePassword();
    await this.storage.setPassword(token, student, password);
    return { password };
  }
}
