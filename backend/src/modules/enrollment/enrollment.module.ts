import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { SupabaseEnrollment } from './infrastructure/supabase-enrollment';
import { EnrollmentController } from './presentation/enrollment.controller';

@Module({
  imports: [AccessModule],
  controllers: [EnrollmentController],
  providers: [{
    provide: SupabaseEnrollment,
    useFactory: () => new SupabaseEnrollment(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
  }],
})
export class EnrollmentModule {}
