import { Module } from '@nestjs/common';
import { requiredEnv } from '../../config';
import { createPaymentProvider } from './infrastructure/provider-factory';
import { SupabasePayments } from './infrastructure/supabase-payments';
import { PAYMENT_PROVIDER, PaymentsController } from './presentation/payments.controller';

@Module({
  controllers: [PaymentsController],
  providers: [
    { provide: PAYMENT_PROVIDER, useFactory: () => createPaymentProvider() },
    {
      provide: SupabasePayments,
      useFactory: () => new SupabasePayments(
        requiredEnv('SUPABASE_URL'),
        requiredEnv('SUPABASE_PUBLISHABLE_KEY'),
        // Sin pasarela configurada el secreto no hace falta: ningún cobro puede confirmarse.
        process.env.PAYMENT_PROVIDER ? requiredEnv('PAYMENT_INTERNAL_SECRET') : 'disabled',
      ),
    },
  ],
})
export class PaymentsModule {}
