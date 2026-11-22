export function requiredEnv(key: string): string {
  const value = (process.env[key] ?? import.meta.env[key])?.trim();
  if (!value) throw new Error(`Missing environment variable: ${key}`);
  return value;
}

export function siteUrl(): URL {
  const value = requiredEnv('SITE_URL');
  if (!URL.canParse(value)) throw new Error('Invalid SITE_URL');
  const url = new URL(value);
  if (url.origin !== value || !['https:', 'http:'].includes(url.protocol)) {
    throw new Error('SITE_URL must be an exact web origin');
  }
  return url;
}

export function publicSupabaseConfig() {
  const url = requiredEnv('SUPABASE_URL');
  const key = requiredEnv('SUPABASE_PUBLISHABLE_KEY');
  const segments = key.split('.');
  if (key.startsWith('sb_secret_') || (segments.length === 3 && legacyRole(segments[1]) === 'service_role')) {
    throw new Error('SUPABASE_PUBLISHABLE_KEY must be public');
  }
  return { url, key };
}

function legacyRole(payload: string): unknown {
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')).role;
  } catch {
    return null;
  }
}
