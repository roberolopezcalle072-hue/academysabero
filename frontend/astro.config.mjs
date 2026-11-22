import { defineConfig, passthroughImageService } from 'astro/config';
import vercel from '@astrojs/vercel';

export default defineConfig({
  output: 'server',
  adapter: vercel(),
  image: { service: passthroughImageService() },
  devToolbar: { enabled: false },
  security: {
    allowedDomains: [
      { protocol: 'https', hostname: 'academy.saberoconsulting.com' },
      { protocol: 'http', hostname: 'localhost' },
      { protocol: 'http', hostname: '127.0.0.1' },
    ],
  },
});
