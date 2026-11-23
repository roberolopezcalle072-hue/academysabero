import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { ScheduleController } from './schedule.controller';
import { SupabaseSchedule } from './supabase-schedule';

@Module({
  imports: [AccessModule],
  controllers: [ScheduleController],
  providers: [{
    provide: SupabaseSchedule,
    useFactory: () => new SupabaseSchedule(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
  }],
})
export class ScheduleModule {}
