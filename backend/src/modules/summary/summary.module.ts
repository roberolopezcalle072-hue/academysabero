import { Module } from '@nestjs/common';
import { AccessModule } from '../access/access.module';
import { SummaryController } from './summary.controller';

@Module({ imports: [AccessModule], controllers: [SummaryController] })
export class SummaryModule {}
