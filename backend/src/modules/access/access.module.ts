import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { ResolveAccess } from './application/resolve-access';
import { SupabaseIdentity } from './infrastructure/supabase-identity';
import { AccessController } from './presentation/access.controller';

@Module({
  controllers: [AccessController],
  exports: [ResolveAccess],
  providers: [{
    provide: ResolveAccess,
    useFactory: () => new ResolveAccess(new SupabaseIdentity(
      requiredEnv('SUPABASE_URL'),
      requiredEnv('SUPABASE_PUBLISHABLE_KEY'),
    )),
  }],
})
export class AccessModule {}
