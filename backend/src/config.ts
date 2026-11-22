export function requiredEnv(key: string): string {
  const value = process.env[key]?.trim();
  if (!value) throw new Error(`Missing environment variable: ${key}`);
  return value;
}

export function allowedBrowserOrigin(): string {
  const value = process.env.CORS_ORIGIN?.trim() ||
    (process.env.NODE_ENV === 'production' ? '' : 'http://localhost:4321');
  if (!URL.canParse(value)) throw new Error('Invalid CORS_ORIGIN');
  const url = new URL(value);
  if (url.origin !== value || !['http:', 'https:'].includes(url.protocol) ||
      (process.env.NODE_ENV === 'production' && url.protocol !== 'https:')) {
    throw new Error('CORS_ORIGIN must be an exact web origin');
  }
  return value;
}
