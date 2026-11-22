import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { ComplaintsController } from './complaints.controller';
import { SupabaseComplaints } from './supabase-complaints';

@Module({
  imports: [AccessModule],
  controllers: [ComplaintsController],
  providers: [{
    provide: SupabaseComplaints,
    useFactory: () => new SupabaseComplaints(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
  }],
})
export class ComplaintsModule {}
