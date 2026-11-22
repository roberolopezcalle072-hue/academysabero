import 'reflect-metadata';
import { ConsoleLogger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { allowedBrowserOrigin } from './config';
import { requestLogging, SafeHttpErrors } from './platform/http/observability';

async function bootstrap() {
  const origin = allowedBrowserOrigin();
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    logger: new ConsoleLogger({ json: process.env.NODE_ENV === 'production' }),
    bodyParser: false,
  });
  app.disable('x-powered-by');
  app.use(requestLogging);
  app.enableCors({
    origin,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    credentials: false,
    maxAge: 600,
  });
  app.useBodyParser('json', { limit: '1mb' });
  app.useGlobalFilters(new SafeHttpErrors());
  app.setGlobalPrefix('api/v1');
  app.enableShutdownHooks();

  const server = app.getHttpServer();
  server.requestTimeout = 15_000;
  server.headersTimeout = 10_000;
  await app.listen(Number(process.env.PORT ?? 3000), process.env.HOST ?? '127.0.0.1');
}

void bootstrap();
