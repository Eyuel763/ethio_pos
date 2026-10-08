import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './modules/auth/auth.module';
import { SyncModule } from './modules/sync/sync.module';
import { LedgerModule } from './modules/ledger/ledger.module';

@Module({
  imports: [PrismaModule, AuthModule, SyncModule, LedgerModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
