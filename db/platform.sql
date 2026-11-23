-- ============================================================================
-- Base de la plataforma para PostgreSQL PURO (sin Supabase).
-- Crea lo mínimo que las migraciones de supabase/migrations esperan encontrar:
--   * roles anon / authenticated / authenticator (los usa PostgREST)
--   * esquema "auth" con usuarios, identidades, sesiones y tokens de refresco
--   * funciones auth.uid() y auth.jwt() (leen los datos del token que PostgREST publica)
--   * esquema "extensions" con pgcrypto (crypt, gen_salt)
-- Se ejecuta UNA vez, antes de las migraciones, con un rol que pueda crear roles y esquemas.
-- ============================================================================

-- Roles. "authenticator" es el único que inicia sesión; PostgREST cambia a anon/authenticated por petición.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator noinherit login; end if;
  -- Las migraciones antiguas conceden permisos a este rol (era el de Supabase Auth). Aquí no tiene uso, solo evita errores.
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then create role supabase_auth_admin nologin; end if;
end
$$;
grant anon, authenticated to authenticator;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to authenticated, anon;

grant usage on schema public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Autenticación propia (la administra el backend; ver backend/src/modules/auth)
-- ---------------------------------------------------------------------------
create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_sign_in_at timestamptz,
  -- Columnas de compatibilidad (las usan las pruebas SQL existentes).
  instance_id uuid,
  aud text,
  role text
);
create unique index if not exists users_email_lower_key on auth.users (lower(email));

create table if not exists auth.identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null,
  provider_id text not null,
  identity_data jsonb not null default '{}'::jsonb,
  last_sign_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_id)
);
create index if not exists identities_user_idx on auth.identities (user_id);

create table if not exists auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  not_after timestamptz,
  user_agent text,
  -- Cómo inició sesión: 'password' u 'oauth' (Google). Los administradores solo pueden entrar con 'oauth'.
  auth_method text not null default 'password' check (auth_method in ('password', 'oauth'))
);
create index if not exists sessions_user_idx on auth.sessions (user_id);

-- Tokens de refresco: solo se guarda el resumen SHA-256, nunca el token.
create table if not exists auth.refresh_tokens (
  id bigserial primary key,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  session_id uuid not null references auth.sessions (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists refresh_tokens_session_idx on auth.refresh_tokens (session_id);

-- Intentos de inicio de sesión (freno contra fuerza bruta).
create table if not exists auth.login_attempts (
  id bigserial primary key,
  email text not null,
  ip text not null,
  succeeded boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists login_attempts_email_idx on auth.login_attempts (lower(email), created_at desc);
create index if not exists login_attempts_ip_idx on auth.login_attempts (ip, created_at desc);

-- PostgREST publica el token verificado en la configuración "request.jwt.claims".
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;

-- Igual que Supabase: primero la configuración clásica "request.jwt.claim.sub", luego el sub del token completo.
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), auth.jwt() ->> 'sub')::uuid;
$$;

grant usage on schema auth to anon, authenticated;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;

-- Las tablas de auth no son accesibles desde la API pública (solo las funciones SECURITY DEFINER y el backend).
revoke all on all tables in schema auth from public, anon, authenticated;
