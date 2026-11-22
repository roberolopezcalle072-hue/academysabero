// Oferta de lanzamiento que se repite en ciclos fijos (cronómetro compartido por toda la web).
export const PROMO = {
  /** Inicio del primer ciclo. Los ciclos siguientes se calculan a partir de esta fecha. */
  anchor: '2026-11-22T00:00:00-05:00',
  cycleDays: 15,
  priceOffer: 199,
  priceRegular: 399,
  currency: 'USD',
};

export const discountPercent = Math.round((1 - PROMO.priceOffer / PROMO.priceRegular) * 100);

/** Instante (ms) en que termina el ciclo de oferta vigente. */
export function promoEnd(now = Date.now()): number {
  const start = Date.parse(PROMO.anchor);
  const cycle = PROMO.cycleDays * 24 * 60 * 60 * 1000;
  if (now < start) return start + cycle;
  return start + (Math.floor((now - start) / cycle) + 1) * cycle;
}

export function remaining(now = Date.now()) {
  const left = Math.max(0, promoEnd(now) - now);
  return {
    days: Math.floor(left / 86_400_000),
    hours: Math.floor(left / 3_600_000) % 24,
    minutes: Math.floor(left / 60_000) % 60,
    seconds: Math.floor(left / 1000) % 60,
  };
}

export const money = (value: number, currency = PROMO.currency) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency, maximumFractionDigits: 0 }).format(value);
