export const prerender = false;
const site = 'https://academy.saberoconsulting.com';
export function GET() {
  const urls = ['/', '/ingresar', '/registro', '/privacidad', '/terminos', '/terminos-compra', '/reembolso', '/libro-de-reclamaciones'];
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((u) => `  <url><loc>${site}${u}</loc></url>`).join('\n')}\n</urlset>\n`;
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600' } });
}
