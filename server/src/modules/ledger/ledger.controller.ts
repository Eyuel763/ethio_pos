import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentShop } from '../auth/decorators/current-shop.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CreateCustomerDto, RecordCloudRepaymentDto } from './dto/ledger.dto';
import { LedgerService } from './ledger.service';

@UseGuards(JwtAuthGuard)
@Controller('api/v1/ledger')
export class LedgerController {
  constructor(private readonly ledgerService: LedgerService) {}

  @Get('metrics')
  async getShopOverviewMetrics(@CurrentShop() shopId: string) {
    return this.ledgerService.getShopOverviewMetrics(shopId);
  }

  @Get('customers')
  async getCustomers(
    @CurrentShop() shopId: string,
    @Query('search') search?: string,
  ) {
    return this.ledgerService.getCustomers(shopId, search);
  }

  @Post('customers')
  async createCustomer(
    @CurrentShop() shopId: string,
    @Body() dto: CreateCustomerDto,
  ) {
    return this.ledgerService.createCustomer(shopId, dto);
  }

  @Get('customers/:id')
  async getCustomerLedgerDetails(
    @CurrentShop() shopId: string,
    @Param('id') customerId: string,
  ) {
    return this.ledgerService.getCustomerLedgerDetails(shopId, customerId);
  }

  @HttpCode(HttpStatus.OK)
  @Post('customers/:id/repayments')
  async recordRepayment(
    @CurrentShop() shopId: string,
    @Param('id') customerId: string,
    @Body() dto: RecordCloudRepaymentDto,
  ) {
    return this.ledgerService.recordRepayment(shopId, customerId, dto);
  }

  @Get('products')
  async getProducts(
    @CurrentShop() shopId: string,
    @Query('low_stock') lowStock?: string,
  ) {
    const isLowStock = lowStock === 'true' || lowStock === '1';
    return this.ledgerService.getProducts(shopId, isLowStock);
  }
}
