import { Global, Module } from '@nestjs/common';
import { createEmailProvider } from './infrastructure/provider-factory';
import { EMAIL_PROVIDER, MailService } from './mail.service';

@Global()
@Module({
  providers: [{ provide: EMAIL_PROVIDER, useFactory: () => createEmailProvider() }, MailService],
  exports: [MailService],
})
export class MailModule {}
