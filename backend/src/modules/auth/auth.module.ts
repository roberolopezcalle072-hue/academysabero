import { Global, Module } from '@nestjs/common';
import { Pool } from 'pg';
import { requiredEnv } from '../../config';
import { loadAuthConfig } from './auth.config';
import { AuthController } from './auth.controller';
import { AuthRepository } from './auth.repository';
import { AuthService } from './auth.service';
import { GoogleOAuth } from './google-oauth';
import { PasswordService } from './password.service';
import { TokenService } from './token.service';

@Global()
@Module({
  controllers: [AuthController],
  exports: [AuthService],
  providers: [{
    provide: AuthService,
    useFactory: () => {
      const config = loadAuthConfig();
      const pool = new Pool({ connectionString: requiredEnv('DATABASE_URL'), max: 5 });
      return new AuthService(
        new AuthRepository(pool),
        new TokenService(config),
        new PasswordService(),
        config,
        config.google ? new GoogleOAuth(config.google.clientId, config.google.clientSecret) : null,
      );
    },
  }],
})
export class AuthModule {}
