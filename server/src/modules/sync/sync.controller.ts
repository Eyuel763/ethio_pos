import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentShop } from '../auth/decorators/current-shop.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { SyncPushDto } from './dto/sync.dto';
import { SyncService } from './sync.service';

@UseGuards(JwtAuthGuard)
@Controller('api/v1/sync')
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @HttpCode(HttpStatus.OK)
  @Post('push')
  async pushMutations(
    @CurrentShop() shopId: string,
    @Body() dto: SyncPushDto,
  ) {
    return this.syncService.processPush(shopId, dto);
  }

  @Get('pull')
  async pullUpdates(
    @CurrentShop() shopId: string,
    @Query('last_synced_at') lastSyncedAt?: string,
  ) {
    return this.syncService.processPull(shopId, lastSyncedAt);
  }
}
