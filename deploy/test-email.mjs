// Prueba el envío de correo con tu llave de Resend, sin tocar el servidor.
// Uso (desde la carpeta del proyecto):   node deploy/test-email.mjs tucorreo@gmail.com
// Requiere haber compilado el backend una vez:  cd backend && npm run build
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const to = process.argv[2];
if (!to || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
  console.error('Indica el correo de destino:  node deploy/test-email.mjs tucorreo@gmail.com');
  process.exit(1);
}

// Lee backend/.env.production (acepta valores entre comillas).
const env = {};
for (const line of readFileSync(path.join(root, 'backend/.env.production'), 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim().replace(/^"(.*)"$/, '$1');
}
if (env.EMAIL_PROVIDER !== 'resend') { console.error('En backend/.env.production falta EMAIL_PROVIDER=resend'); process.exit(1); }
if (!env.RESEND_API_KEY || env.RESEND_API_KEY.includes('PEGAR')) { console.error('Pega tu llave en RESEND_API_KEY dentro de backend/.env.production'); process.exit(1); }

const require = createRequire(import.meta.url);
let ResendProvider;
try {
  ({ ResendProvider } = require(path.join(root, 'backend/dist/modules/mail/infrastructure/resend-provider.js')));
} catch {
  console.error('Primero compila el backend:  cd backend && npm run build');
  process.exit(1);
}

const from = env.EMAIL_FROM || 'SABERO Academy <no-reply@saberoconsulting.com>';
console.log(`Enviando prueba desde "${from}" hacia ${to} ...`);
try {
  await new ResendProvider(env.RESEND_API_KEY, from).send({
    to: [to],
    subject: 'Prueba de correo · SABERO Academy',
    html: '<p style="font-family:Arial,sans-serif">¡Funciona! Este es un correo de prueba de <b>SABERO Academy</b>.</p>',
    text: '¡Funciona! Este es un correo de prueba de SABERO Academy.',
  });
  console.log('✔ Correo enviado. Revisa tu bandeja (y la carpeta de spam).');
} catch (error) {
  console.error('✘ No se pudo enviar:', error.message);
  if (/not verified|domain/i.test(error.message)) {
    console.error('\nEl dominio del remitente aún no está verificado en Resend. Mientras tanto puedes probar con:');
    console.error('  EMAIL_FROM="SABERO Academy <onboarding@resend.dev>"   (solo permite enviar a tu propio correo de Resend)');
  }
  process.exit(1);
}
