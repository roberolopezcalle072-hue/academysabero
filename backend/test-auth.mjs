// Prueba de integración del módulo auth contra PostgreSQL puro. Uso: node test-auth.mjs (después de npm run build)
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { Pool } from 'pg';
const require = createRequire(import.meta.url);
const { AuthRepository } = require('./dist/modules/auth/auth.repository');
const { AuthService } = require('./dist/modules/auth/auth.service');
const { TokenService } = require('./dist/modules/auth/token.service');
const { PasswordService } = require('./dist/modules/auth/password.service');

const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 3 });
const config = {
  jwtSecret: new TextEncoder().encode('x'.repeat(40)), accessTtl: 3600, refreshTtl: 86400,
  siteUrl: 'https://academy.saberoconsulting.com', google: null,
};
const fakeGoogle = { exchange: async (code) => ({ sub: 'g-' + code, email: code + '@gmail.com', emailVerified: true, name: 'Gente ' + code }) };
const svc = new AuthService(new AuthRepository(pool), new TokenService(config), new PasswordService(), config, fakeGoogle);
const req = { ip: '9.9.9.9', userAgent: 'test' };
const rejects = async (p, status) => {
  try { await p; } catch (e) { assert.equal(e.getStatus?.(), status, `esperaba ${status}, llegó ${e.message}`); return; }
  assert.fail(`esperaba rechazo ${status}`);
};

await pool.query(`delete from auth.users where email like '%@test.local' or email like '%@gmail.com'`);

// registro + login
const s1 = await svc.signUp('Ana@Test.local', 'clave-segura-1', 'Ana', req);
assert.equal(s1.user.email, 'ana@test.local');
await rejects(svc.signUp('ana@test.local', 'otra-clave-123', 'Ana', req), 409);
await rejects(svc.signUp('mala', 'clave-segura-1', '', req), 400);
await rejects(svc.signUp('b@test.local', 'corta', '', req), 400);
assert.ok(await svc.verify(s1.accessToken));
const login = await svc.login('ana@test.local', 'clave-segura-1', req);
assert.ok(await svc.verify(login.accessToken));

// el hash de bcryptjs lo entiende pgcrypto (y al revés: compatibilidad con restablecimiento por administración)
const { rows: [{ ok }] } = await pool.query(`select extensions.crypt('clave-segura-1', encrypted_password) = encrypted_password as ok from auth.users where email='ana@test.local'`);
assert.equal(ok, true);
await pool.query(`update auth.users set encrypted_password = extensions.crypt('desde-pgcrypto-1', extensions.gen_salt('bf')) where email='ana@test.local'`);
assert.ok(await svc.login('ana@test.local', 'desde-pgcrypto-1', req));

// fuerza bruta
for (let i = 0; i < 5; i++) await rejects(svc.login('ana@test.local', 'mala-clave-xx', { ip: '1.1.1.1', userAgent: null }), 401);
await rejects(svc.login('ana@test.local', 'desde-pgcrypto-1', { ip: '2.2.2.2', userAgent: null }), 429);
await pool.query(`delete from auth.login_attempts`);

// refresco con rotación y reutilización
const r1 = await svc.refresh(login.refreshToken);
assert.ok(await svc.verify(r1.accessToken));
await rejects(svc.refresh(login.refreshToken), 401);
await rejects(svc.refresh('inventado'), 401);

// cierre de sesión revoca el token de acceso al instante
await svc.logout((await svc.verify(r1.accessToken)).sessionId);
assert.equal(await svc.verify(r1.accessToken), null);

// token falso / vencido
assert.equal(await svc.verify('abc.def.ghi'), null);
const expired = new AuthService(new AuthRepository(pool), new TokenService({ ...config, accessTtl: -10 }), new PasswordService(), config, null);
const old = await expired.login('ana@test.local', 'desde-pgcrypto-1', req);
assert.equal(await svc.verify(old.accessToken), null);

// cambio de contraseña
const a = await svc.login('ana@test.local', 'desde-pgcrypto-1', req);
const b = await svc.login('ana@test.local', 'desde-pgcrypto-1', req);
await rejects(svc.changePassword(a.user.id, (await svc.verify(a.accessToken)).sessionId, 'incorrecta-1', 'nueva-clave-99'), 403);
await svc.changePassword(a.user.id, (await svc.verify(a.accessToken)).sessionId, 'desde-pgcrypto-1', 'nueva-clave-99');
assert.ok(await svc.verify(a.accessToken));
assert.equal(await svc.verify(b.accessToken), null, 'las otras sesiones se cierran');
assert.ok(await svc.login('ana@test.local', 'nueva-clave-99', req));

// Google: crea, reutiliza, vincula por correo y valida el retorno
const g1 = await svc.loginWithGoogle('luis', 'v', 'https://academy.saberoconsulting.com/auth/callback', req);
const g2 = await svc.loginWithGoogle('luis', 'v', 'https://academy.saberoconsulting.com/auth/callback', req);
assert.equal(g1.user.id, g2.user.id);
await rejects(svc.loginWithGoogle('luis', 'v', 'https://malo.example/auth/callback', req), 400);
await pool.query(`insert into auth.users (email, email_confirmed_at) values ('ana2@gmail.com', now())`);
const linked = await svc.loginWithGoogle('ana2', 'v', 'https://academy.saberoconsulting.com/auth/callback', req);
assert.equal(linked.user.email, 'ana2@gmail.com');

// administración: no entra con contraseña, sí con Google
const admin = await svc.signUp('jefe@test.local', 'clave-jefe-123', 'Jefe', req);
await pool.query(`insert into public.academy_members (user_id, role) values ($1, 'admin')`, [admin.user.id]);
await rejects(svc.login('jefe@test.local', 'clave-jefe-123', req), 403);

// correo revocado
await pool.query(`insert into public.academy_authorized_emails (email, active) values ('veto@test.local', false) on conflict (email) do update set active=false`);
await rejects(svc.signUp('veto@test.local', 'clave-segura-1', '', req), 403);

await pool.query(`delete from public.academy_authorized_emails where email = 'veto@test.local'`);
await pool.query(`delete from public.academy_members where user_id = $1`, [admin.user.id]);
await pool.query(`delete from auth.users where email like '%@test.local' or email like '%@gmail.com'`);
await pool.end();
console.log('AUTH OK');
