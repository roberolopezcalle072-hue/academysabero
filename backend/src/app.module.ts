import { Module } from '@nestjs/common';
import { AccessModule } from './modules/access/access.module';
import { AccessAdminModule } from './modules/access-admin/access-admin.module';
import { EnrollmentModule } from './modules/enrollment/enrollment.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { ComplaintsModule } from './modules/complaints/complaints.module';
import { LearningModule } from './modules/learning/learning.module';
import { LiveTrainingModule } from './modules/live-training/live-training.module';
import { HealthController } from './modules/health/health.controller';

@Module({ imports: [AccessModule, AccessAdminModule, EnrollmentModule, PaymentsModule, ComplaintsModule, LearningModule, LiveTrainingModule], controllers: [HealthController] })
export class AppModule {}
