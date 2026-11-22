import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { ManageAccess } from './application/manage-access';
import { SupabaseAdministration } from './infrastructure/supabase-administration';
import { AccessAdminController } from './presentation/access-admin.controller';

@Module({
  imports: [AccessModule],
  controllers: [AccessAdminController],
  providers: [{
    provide: ManageAccess,
    useFactory: () => new ManageAccess(new SupabaseAdministration(
      requiredEnv('SUPABASE_URL'),
      requiredEnv('SUPABASE_PUBLISHABLE_KEY'),
    )),
  }],
})
export class AccessAdminModule {}
