const UNITS = ['', 'UN', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE', 'DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE',
  'DIECISÉIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE', 'VEINTE', 'VEINTIÚN', 'VEINTIDÓS', 'VEINTITRÉS', 'VEINTICUATRO', 'VEINTICINCO',
  'VEINTISÉIS', 'VEINTISIETE', 'VEINTIOCHO', 'VEINTINUEVE'];
const TENS = ['', '', '', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'];
const HUNDREDS = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS'];

function below1000(n: number): string {
  if (n === 100) return 'CIEN';
  const h = Math.floor(n / 100);
  const rest = n % 100;
  const parts: string[] = [];
  if (h) parts.push(HUNDREDS[h]);
  if (rest) {
    if (rest < 30) parts.push(UNITS[rest]);
    else parts.push(TENS[Math.floor(rest / 10)] + (rest % 10 ? ` Y ${UNITS[rest % 10]}` : ''));
  }
  return parts.join(' ');
}

function integerInWords(n: number): string {
  if (n === 0) return 'CERO';
  if (n < 1000) return below1000(n);
  const thousands = Math.floor(n / 1000);
  const rest = n % 1000;
  const head = thousands === 1 ? 'UN MIL' : `${below1000(thousands)} MIL`;
  return rest ? `${head} ${below1000(rest)}` : head;
}

/** Ejemplo: 749.5 PEN -> "SON: SETECIENTOS CUARENTA Y NUEVE Y 50/100 SOLES". Admite hasta 999 999. */
export function amountInWords(amount: number, currency: string): string {
  const total = Math.round(amount * 100);
  const whole = Math.floor(total / 100);
  const cents = String(total % 100).padStart(2, '0');
  const name = currency === 'PEN' ? 'SOLES' : currency === 'USD' ? 'DÓLARES AMERICANOS' : currency;
  // Al final de la cifra se dice "uno", no "un" (CIENTO UNO, VEINTIUNO).
  const words = integerInWords(Math.min(whole, 999_999)).replace(/VEINTIÚN$/, 'VEINTIUNO').replace(/(^| )UN$/, '$1UNO');
  return `SON: ${words} Y ${cents}/100 ${name}`;
}
