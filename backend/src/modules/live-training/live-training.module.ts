import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { SupabaseLiveTraining } from './infrastructure/supabase-live-training';
import { LIVE_TRAINING, LiveTrainingController } from './presentation/live-training.controller';

@Module({
  imports: [AccessModule],
  controllers: [LiveTrainingController],
  providers: [{
    provide: LIVE_TRAINING,
    useFactory: () => new SupabaseLiveTraining(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
  }],
})
export class LiveTrainingModule {}
