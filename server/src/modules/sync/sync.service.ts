import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import {
  EntityType,
  MutationDto,
  SyncOperation,
  SyncPushDto,
  SyncPushResponseDto,
  SyncResultItemDto,
} from './dto/sync.dto';

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Process batched mutations pushed from the offline client.
   * Enforces:
   * 1. Multi-tenant shop boundary
   * 2. Idempotency on (shopId, entityId, operation)
   * 3. Relative stock decrements (delta-based) on sales
   * 4. Dynamic computed customer credit balances
   */
  async processPush(shopId: string, dto: SyncPushDto): Promise<SyncPushResponseDto> {
    if (shopId !== dto.shop_id) {
      throw new BadRequestException('Shop ID in payload does not match authenticated shop');
    }

    const results: SyncResultItemDto[] = [];

    for (const mutation of dto.mutations) {
      try {
        const result = await this.processSingleMutation(shopId, mutation);
        results.push(result);
      } catch (err: any) {
        this.logger.error(`Error processing sync mutation ${mutation.sync_id}: ${err.message}`, err.stack);
        results.push({
          sync_id: mutation.sync_id,
          status: 'FAILED',
          entity_id: mutation.entity_id,
          error: err.message || 'Unknown processing error',
        });
      }
    }

    return {
      status: 'success',
      processed_at: new Date().toISOString(),
      results,
    };
  }

  private async processSingleMutation(
    shopId: string,
    mutation: MutationDto,
  ): Promise<SyncResultItemDto> {
    // 1. Idempotency Check: Check if this specific mutation was already processed
    const alreadyProcessed = await this.prisma.processedMutation.findUnique({
      where: {
        shopId_entityId_operation: {
          shopId,
          entityId: mutation.entity_id,
          operation: mutation.operation,
        },
      },
    });

    if (alreadyProcessed) {
      this.logger.log(`Idempotent hit: mutation ${mutation.entity_id} (${mutation.operation}) already processed. Acknowledging.`);
      return {
        sync_id: mutation.sync_id,
        status: 'SUCCESS',
        entity_id: mutation.entity_id,
      };
    }

    // 2. Process according to entity type inside an isolated database transaction
    await this.prisma.$transaction(async (tx) => {
      switch (mutation.entity_type) {
        case EntityType.SALE:
          await this.processSaleMutation(tx, shopId, mutation);
          break;

        case EntityType.PRODUCT:
          await this.processProductMutation(tx, shopId, mutation);
          break;

        case EntityType.CUSTOMER:
          await this.processCustomerMutation(tx, shopId, mutation);
          break;

        case EntityType.DEBT_REPAYMENT:
          await this.processRepaymentMutation(tx, shopId, mutation);
          break;

        default:
          throw new BadRequestException(`Unsupported entity type: ${mutation.entity_type}`);
      }

      // Record in ProcessedMutation table for strict idempotence
      await tx.processedMutation.create({
        data: {
          shopId,
          syncId: mutation.sync_id,
          entityType: mutation.entity_type,
          entityId: mutation.entity_id,
          operation: mutation.operation,
        },
      });
    });

    return {
      sync_id: mutation.sync_id,
      status: 'SUCCESS',
      entity_id: mutation.entity_id,
    };
  }

  /**
   * Processes a sale mutation:
   * - Records sale header and item snapshots
   * - Applies delta-based stock decrements atomically: stock = stock - quantity
   * - Updates customer total_debt balance if sold on credit
   */
  private async processSaleMutation(
    tx: Prisma.TransactionClient,
    shopId: string,
    mutation: MutationDto,
  ) {
    const data = mutation.data;

    // Check if sale already exists
    const existingSale = await tx.sale.findUnique({
      where: { id: mutation.entity_id },
    });
    if (existingSale) {
      return; // Already recorded
    }

    // Ensure customer exists if customer_id provided
    if (data.customer_id) {
      const customer = await tx.customer.findUnique({
        where: { id: data.customer_id },
      });
      if (!customer) {
        // Create a stub customer if created offline on client
        await tx.customer.create({
          data: {
            id: data.customer_id,
            shopId,
            fullName: 'Unknown Customer',
          },
        });
      }
    }

    const paymentType = data.payment_type || 'cash';
    if (!['cash', 'mobile_transfer', 'credit'].includes(paymentType)) {
      throw new BadRequestException(`Invalid payment_type: ${paymentType}. Allowed: cash, mobile_transfer, credit`);
    }

    // 1. Create Sale Header
    await tx.sale.create({
      data: {
        id: mutation.entity_id,
        shopId,
        customerId: data.customer_id || null,
        paymentType,
        subtotal: new Prisma.Decimal(data.subtotal ?? 0),
        discount: new Prisma.Decimal(data.discount ?? 0),
        grandTotal: new Prisma.Decimal(data.grand_total ?? 0),
        amountPaid: new Prisma.Decimal(data.amount_paid ?? 0),
        amountDue: new Prisma.Decimal(data.amount_due ?? 0),
        createdAt: data.created_at ? new Date(data.created_at) : new Date(),
      },
    });

    // 2. Process Line Items and Delta Stock Decrements
    if (Array.isArray(data.items)) {
      for (const item of data.items) {
        // Ensure product exists
        const existingProduct = await tx.product.findUnique({
          where: { id: item.product_id },
        });

        if (!existingProduct) {
          // If product doesn't exist on server, stub it
          await tx.product.create({
            data: {
              id: item.product_id,
              shopId,
              nameAm: item.product_name || 'Product',
              nameEn: item.product_name || 'Product',
              sellingPrice: new Prisma.Decimal(item.unit_price ?? 0),
              stockQuantity: new Prisma.Decimal(-(item.quantity ?? 1)),
            },
          });
        } else {
          // DELTA ARITHMETIC: stock_quantity = stock_quantity - sold_quantity
          await tx.product.update({
            where: { id: item.product_id },
            data: {
              stockQuantity: {
                decrement: new Prisma.Decimal(item.quantity ?? 1),
              },
            },
          });
        }

        // Insert item snapshot
        await tx.saleItem.create({
          data: {
            id: item.id,
            saleId: mutation.entity_id,
            productId: item.product_id,
            productName: item.product_name || 'Product',
            unitPrice: new Prisma.Decimal(item.unit_price ?? 0),
            quantity: new Prisma.Decimal(item.quantity ?? 1),
            totalPrice: new Prisma.Decimal(item.total_price ?? 0),
          },
        });
      }
    }

    // 3. Update customer balance if credit sale
    if (data.customer_id && Number(data.amount_due) > 0) {
      await this.recalculateCustomerBalance(tx, shopId, data.customer_id);
    }
  }

  /**
   * Processes a customer debt repayment:
   * - Records repayment row
   * - Dynamically recalculates customer balance
   */
  private async processRepaymentMutation(
    tx: Prisma.TransactionClient,
    shopId: string,
    mutation: MutationDto,
  ) {
    const data = mutation.data;

    const existing = await tx.debtRepayment.findUnique({
      where: { id: mutation.entity_id },
    });
    if (existing) {
      return;
    }

    await tx.debtRepayment.create({
      data: {
        id: mutation.entity_id,
        shopId,
        customerId: data.customer_id,
        amount: new Prisma.Decimal(data.amount ?? 0),
        paymentMethod: data.payment_method || 'cash',
        note: data.note || null,
        createdAt: data.created_at ? new Date(data.created_at) : new Date(),
      },
    });

    // Recalculate customer total_debt balance
    await this.recalculateCustomerBalance(tx, shopId, data.customer_id);
  }

  /**
   * Upsert or soft-delete products.
   */
  private async processProductMutation(
    tx: Prisma.TransactionClient,
    shopId: string,
    mutation: MutationDto,
  ) {
    const data = mutation.data;

    if (mutation.operation === SyncOperation.DELETE) {
      await tx.product.updateMany({
        where: { id: mutation.entity_id, shopId },
        data: { isDeleted: true },
      });
      return;
    }

    const existing = await tx.product.findUnique({
      where: { id: mutation.entity_id },
    });

    if (!existing) {
      await tx.product.create({
        data: {
          id: mutation.entity_id,
          shopId,
          barcode: data.barcode || null,
          nameAm: data.name_am || data.name_en || 'Product',
          nameEn: data.name_en || data.name_am || 'Product',
          category: data.category || 'General',
          unitType: data.unit_type || 'piece',
          sellingPrice: new Prisma.Decimal(data.selling_price ?? 0),
          costPrice: new Prisma.Decimal(data.cost_price ?? 0),
          stockQuantity: new Prisma.Decimal(data.stock_quantity ?? (data.stock_delta ?? 0)),
          minStockLevel: new Prisma.Decimal(data.min_stock_level ?? 5),
          isDeleted: data.is_deleted ?? false,
        },
      });
    } else {
      let stockUpdate: Prisma.DecimalFieldUpdateOperationsInput | Prisma.Decimal | undefined;
      if (data.stock_delta !== undefined && data.stock_delta !== null) {
        stockUpdate = { increment: new Prisma.Decimal(data.stock_delta) };
      } else if (data.stock_quantity !== undefined && data.stock_quantity !== null) {
        if (Number(existing.stockQuantity) < 0 && mutation.operation === SyncOperation.CREATE) {
          // Reconcile stubbed sales with initial stock count
          stockUpdate = new Prisma.Decimal(data.stock_quantity).plus(existing.stockQuantity);
        } else {
          stockUpdate = new Prisma.Decimal(data.stock_quantity);
        }
      }

      await tx.product.update({
        where: { id: mutation.entity_id },
        data: {
          barcode: data.barcode !== undefined ? data.barcode : undefined,
          nameAm: data.name_am ?? undefined,
          nameEn: data.name_en ?? undefined,
          category: data.category ?? undefined,
          unitType: data.unit_type ?? undefined,
          sellingPrice:
            data.selling_price !== undefined && data.selling_price !== null
              ? new Prisma.Decimal(data.selling_price)
              : undefined,
          costPrice:
            data.cost_price !== undefined && data.cost_price !== null
              ? new Prisma.Decimal(data.cost_price)
              : undefined,
          stockQuantity: stockUpdate,
          minStockLevel:
            data.min_stock_level !== undefined && data.min_stock_level !== null
              ? new Prisma.Decimal(data.min_stock_level)
              : undefined,
          isDeleted: data.is_deleted !== undefined ? data.is_deleted : undefined,
        },
      });
    }
  }

  /**
   * Upsert or soft-delete customers.
   */
  private async processCustomerMutation(
    tx: Prisma.TransactionClient,
    shopId: string,
    mutation: MutationDto,
  ) {
    const data = mutation.data;

    if (mutation.operation === SyncOperation.DELETE) {
      await tx.customer.updateMany({
        where: { id: mutation.entity_id, shopId },
        data: { isDeleted: true },
      });
      return;
    }

    await tx.customer.upsert({
      where: { id: mutation.entity_id },
      create: {
        id: mutation.entity_id,
        shopId,
        fullName: data.full_name,
        phoneNumber: data.phone_number || null,
        isDeleted: data.is_deleted || false,
      },
      update: {
        fullName: data.full_name,
        phoneNumber: data.phone_number !== undefined ? data.phone_number : undefined,
        isDeleted: data.is_deleted !== undefined ? data.is_deleted : undefined,
      },
    });
  }

  /**
   * Dynamically computes customer balance from total credit sales - total repayments:
   * Total Debt = Sum(Sales amount_due) - Sum(Repayments amount)
   */
  private async recalculateCustomerBalance(
    tx: Prisma.TransactionClient,
    shopId: string,
    customerId: string,
  ) {
    const creditSales = await tx.sale.aggregate({
      where: { shopId, customerId },
      _sum: { amountDue: true },
    });

    const repayments = await tx.debtRepayment.aggregate({
      where: { shopId, customerId },
      _sum: { amount: true },
    });

    const totalCredit = creditSales._sum.amountDue ? Number(creditSales._sum.amountDue) : 0;
    const totalRepaid = repayments._sum.amount ? Number(repayments._sum.amount) : 0;
    const computedDebt = Math.max(0, totalCredit - totalRepaid);

    await tx.customer.update({
      where: { id: customerId },
      data: {
        totalDebt: new Prisma.Decimal(computedDebt),
      },
    });
  }

  /**
   * Pulls entities updated since `last_synced_at` for the specified shop.
   */
  async processPull(shopId: string, lastSyncedAt?: string) {
    const since = lastSyncedAt ? new Date(lastSyncedAt) : new Date(0);

    const [products, customers] = await Promise.all([
      this.prisma.product.findMany({
        where: {
          shopId,
          updatedAt: { gte: since },
        },
      }),
      this.prisma.customer.findMany({
        where: {
          shopId,
          updatedAt: { gte: since },
        },
      }),
    ]);

    return {
      status: 'success',
      server_timestamp: new Date().toISOString(),
      data: {
        products,
        customers,
      },
    };
  }
}
