import type { Pool } from 'pg';

export interface UserRow {
  id: string;
  email: string | null;
  encrypted_password: string | null;
  name: string;
}

export interface SessionRow {
  id: string;
  user_id: string;
  auth_method: 'password' | 'oauth';
}

const USER_COLUMNS = `id, email, encrypted_password,
  coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', '') as name`;

/** Acceso a las tablas del esquema "auth" (solo el backend las toca). */
export class AuthRepository {
  constructor(private readonly db: Pool) {}

  async findUserByEmail(email: string): Promise<UserRow | null> {
    const { rows } = await this.db.query<UserRow>(
      `select ${USER_COLUMNS} from auth.users where lower(email) = lower($1)`, [email]);
    return rows[0] ?? null;
  }

  async findUserById(id: string): Promise<UserRow | null> {
    const { rows } = await this.db.query<UserRow>(
      `select ${USER_COLUMNS} from auth.users where id = $1`, [id]);
    return rows[0] ?? null;
  }

  /** Crea una cuenta con correo y contraseña. Devuelve null si el correo ya existe. */
  async createPasswordUser(email: string, passwordHash: string, name: string): Promise<UserRow | null> {
    const { rows } = await this.db.query<UserRow>(
      `insert into auth.users (email, encrypted_password, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, aud, role)
       values ($1, $2, now(), jsonb_build_object('full_name', $3::text), '{"provider":"email"}'::jsonb, 'authenticated', 'authenticated')
       on conflict do nothing
       returning id, email, encrypted_password, $3::text as name`, [email, passwordHash, name]);
    return rows[0] ?? null;
  }

  /** Usuario de Google: se enlaza por identidad y, si el correo ya existía, se vincula a esa cuenta. */
  async upsertGoogleUser(sub: string, email: string, name: string): Promise<UserRow> {
    const client = await this.db.connect();
    try {
      await client.query('begin');
      const linked = await client.query<{ user_id: string }>(
        `select user_id from auth.identities where provider = 'google' and provider_id = $1`, [sub]);
      let userId = linked.rows[0]?.user_id;
      if (!userId) {
        const existing = await client.query<{ id: string }>(
          `select id from auth.users where lower(email) = lower($1) for update`, [email]);
        userId = existing.rows[0]?.id;
        if (!userId) {
          const created = await client.query<{ id: string }>(
            `insert into auth.users (email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, aud, role)
             values ($1, now(), jsonb_build_object('full_name', $2::text), '{"provider":"google"}'::jsonb, 'authenticated', 'authenticated')
             returning id`, [email, name]);
          userId = created.rows[0].id;
        } else {
          await client.query(
            `update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = $1`, [userId]);
        }
        await client.query(
          `insert into auth.identities (user_id, provider, provider_id, identity_data, last_sign_in_at)
           values ($1, 'google', $2, jsonb_build_object('email', $3::text, 'name', $4::text, 'email_verified', 'true'), now())`,
          [userId, sub, email, name]);
      }
      await client.query('commit');
      return (await this.findUserById(userId))!;
    } catch (error) {
      await client.query('rollback').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  /** Correos revocados por la administración (reemplaza al antiguo gancho de Supabase). */
  async isEmailRevoked(email: string): Promise<boolean> {
    const { rowCount } = await this.db.query(
      `select 1 from public.academy_authorized_emails where email = lower($1) and not active`, [email]);
    return (rowCount ?? 0) > 0;
  }

  async isAdmin(userId: string): Promise<boolean> {
    const { rowCount } = await this.db.query(
      `select 1 from public.academy_members where user_id = $1 and role = 'admin' and active`, [userId]);
    return (rowCount ?? 0) > 0;
  }

  async createSession(userId: string, method: 'password' | 'oauth', userAgent: string | null,
                      refreshHash: string, refreshExpires: Date): Promise<string> {
    const client = await this.db.connect();
    try {
      await client.query('begin');
      const { rows } = await client.query<{ id: string }>(
        `insert into auth.sessions (user_id, auth_method, user_agent, not_after) values ($1, $2, $3, $4) returning id`,
        [userId, method, userAgent?.slice(0, 300) ?? null, refreshExpires]);
      await client.query(
        `insert into auth.refresh_tokens (token_hash, session_id, expires_at) values ($1, $2, $3)`,
        [refreshHash, rows[0].id, refreshExpires]);
      await client.query(`update auth.users set last_sign_in_at = now() where id = $1`, [userId]);
      await client.query('commit');
      return rows[0].id;
    } catch (error) {
      await client.query('rollback').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  /** Rota el token de refresco: se consume (un solo uso) y se guarda el siguiente. */
  async rotateRefresh(oldHash: string, newHash: string, newExpires: Date): Promise<SessionRow | null> {
    const client = await this.db.connect();
    try {
      await client.query('begin');
      const found = await client.query<{ session_id: string; expires_at: Date }>(
        `delete from auth.refresh_tokens where token_hash = $1 returning session_id, expires_at`, [oldHash]);
      const token = found.rows[0];
      if (!token) { await client.query('rollback'); return null; }
      const session = await client.query<SessionRow>(
        `select id, user_id, auth_method from auth.sessions
          where id = $1 and (not_after is null or not_after > now())`, [token.session_id]);
      if (!session.rows[0] || token.expires_at.getTime() < Date.now()) {
        await client.query('commit');
        return null;
      }
      await client.query(
        `insert into auth.refresh_tokens (token_hash, session_id, expires_at) values ($1, $2, $3)`,
        [newHash, token.session_id, newExpires]);
      await client.query(`update auth.sessions set updated_at = now(), not_after = $2 where id = $1`,
        [token.session_id, newExpires]);
      await client.query('commit');
      return session.rows[0];
    } catch (error) {
      await client.query('rollback').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async sessionIsActive(sessionId: string, userId: string): Promise<boolean> {
    const { rowCount } = await this.db.query(
      `select 1 from auth.sessions where id = $1 and user_id = $2 and (not_after is null or not_after > now())`,
      [sessionId, userId]);
    return (rowCount ?? 0) > 0;
  }

  async deleteSession(sessionId: string) {
    await this.db.query(`delete from auth.sessions where id = $1`, [sessionId]);
  }

  /** Cierra todas las sesiones salvo la indicada (al cambiar la contraseña). */
  async deleteOtherSessions(userId: string, keepSessionId: string) {
    await this.db.query(`delete from auth.sessions where user_id = $1 and id <> $2`, [userId, keepSessionId]);
  }

  async setPassword(userId: string, hash: string) {
    await this.db.query(
      `update auth.users set encrypted_password = $2, updated_at = now() where id = $1`, [userId, hash]);
  }

  async recentFailures(email: string, ip: string): Promise<{ byEmail: number; byIp: number }> {
    const { rows } = await this.db.query<{ by_email: string; by_ip: string }>(
      `select count(*) filter (where lower(email) = lower($1)) as by_email,
              count(*) filter (where ip = $2) as by_ip
         from auth.login_attempts
        where not succeeded and created_at > now() - interval '15 minutes'`, [email, ip]);
    return { byEmail: Number(rows[0].by_email), byIp: Number(rows[0].by_ip) };
  }

  async recordAttempt(email: string, ip: string, succeeded: boolean) {
    await this.db.query(`insert into auth.login_attempts (email, ip, succeeded) values ($1, $2, $3)`, [email, ip, succeeded]);
    if (succeeded) {
      await this.db.query(`delete from auth.login_attempts where lower(email) = lower($1) and not succeeded`, [email]);
    }
    await this.db.query(`delete from auth.login_attempts where created_at < now() - interval '1 day'`);
  }
}
