import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { AccessModule } from '../access/access.module';
import { SupabaseLearning } from './infrastructure/supabase-learning';
import { SupabaseEditorial } from './infrastructure/supabase-editorial';
import { LearningController, LEARNING_REPOSITORY } from './presentation/learning.controller';
import { EditorialController, EDITORIAL_REPOSITORY } from './presentation/editorial.controller';

@Module({
  imports: [AccessModule],
  controllers: [LearningController, EditorialController],
  providers: [
    {
      provide: LEARNING_REPOSITORY,
      useFactory: () => new SupabaseLearning(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
    },
    {
      provide: EDITORIAL_REPOSITORY,
      useFactory: () => new SupabaseEditorial(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_PUBLISHABLE_KEY')),
    },
  ],
})
export class LearningModule {}
