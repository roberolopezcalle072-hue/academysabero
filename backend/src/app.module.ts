import { Module } from '@nestjs/common';
import { AccessModule } from './modules/access/access.module';
import { AccessAdminModule } from './modules/access-admin/access-admin.module';
import { EnrollmentModule } from './modules/enrollment/enrollment.module';
import { LearningModule } from './modules/learning/learning.module';
import { LiveTrainingModule } from './modules/live-training/live-training.module';
import { HealthController } from './modules/health/health.controller';

@Module({ imports: [AccessModule, AccessAdminModule, EnrollmentModule, LearningModule, LiveTrainingModule], controllers: [HealthController] })
export class AppModule {}
