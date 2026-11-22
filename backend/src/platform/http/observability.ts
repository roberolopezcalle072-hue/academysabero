import { randomUUID } from 'node:crypto';
import { ArgumentsHost, Catch, type ExceptionFilter, HttpException, Logger } from '@nestjs/common';

type ApiRequest = { method: string; academyRequestId?: string };
type ApiResponse = {
  statusCode: number;
  status(code: number): ApiResponse;
  json(body: unknown): void;
  setHeader(name: string, value: string): void;
  once(event: 'finish', listener: () => void): void;
};

export function requestLogging(request: ApiRequest, response: ApiResponse, next: () => void) {
  const logger = new Logger('HTTP');
  const id = randomUUID();
  const started = performance.now();
  request.academyRequestId = id;
  response.setHeader('X-Request-ID', id);
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.once('finish', () => {
    const entry = { requestId: id, method: request.method, status: response.statusCode,
      durationMs: Math.round(performance.now() - started) };
    if (entry.status >= 500) logger.error(entry);
    else logger.log(entry);
  });
  next();
}

@Catch()
export class SafeHttpErrors implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    const context = host.switchToHttp();
    const response = context.getResponse<ApiResponse>();
    if (error instanceof HttpException) {
      const statusCode = error.getStatus();
      const body = error.getResponse();
      response.status(statusCode).json(
        statusCode >= 500 ? { statusCode, message: statusCode === 503 ? 'Service Unavailable' : 'Internal Server Error' } :
          typeof body === 'string' ? { statusCode, message: body } : body,
      );
      return;
    }

    const incomingStatus = typeof error === 'object' && error !== null && 'status' in error
      ? error.status : undefined;
    const statusCode = incomingStatus === 400 || incomingStatus === 413 || incomingStatus === 415
      ? incomingStatus : 500;
    const message = { 400: 'Bad Request', 413: 'Payload Too Large', 415: 'Unsupported Media Type', 500: 'Internal Server Error' };
    response.status(statusCode).json({ statusCode, message: message[statusCode] });
  }
}
