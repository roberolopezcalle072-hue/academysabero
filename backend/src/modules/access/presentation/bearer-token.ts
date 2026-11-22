import { UnauthorizedException } from '@nestjs/common';

export function bearerToken(authorization?: string): string {
  const token = authorization?.match(/^Bearer ([^\s]+)$/i)?.[1];
  if (!token) throw new UnauthorizedException();
  return token;
}
