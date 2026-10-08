import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateCustomerDto, RecordCloudRepaymentDto } from './dto/ledger.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class LedgerService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Returns high-level dashboard metrics for the shop:
   * - Total outstanding debt (ጠቅላላ ያልተከፈለ ዕዳ)
   * - Total completed sales volume
   * - Total product count & low stock warning count
   */
  async getShopOverviewMetrics(shopId: string) {
    const [debtAggregate, salesAggregate, totalProducts, lowStockProducts] =
      await Promise.all([
        this.prisma.customer.aggregate({
          where: { shopId, isDeleted: false },
          _sum: { totalDebt: true },
          _count: { id: true },
        }),
        this.prisma.sale.aggregate({
          where: { shopId },
          _sum: { grandTotal: true, amountPaid: true, amountDue: true },
          _count: { id: true },
        }),
        this.prisma.product.count({
          where: { shopId, isDeleted: false },
        }),
        this.prisma.$queryRaw<{ count: bigint }[]>`
          SELECT COUNT(*)::bigint AS count
          FROM products
          WHERE shop_id = ${shopId}
            AND is_deleted = false
            AND stock_quantity <= min_stock_level
        `,
      ]);

    return {
      totalOutstandingDebt: Number(debtAggregate._sum.totalDebt || 0),
      totalCustomersWithTabs: debtAggregate._count.id,
      totalSalesRevenue: Number(salesAggregate._sum.grandTotal || 0),
      totalCashCollected: Number(salesAggregate._sum.amountPaid || 0),
      totalSalesTransactions: salesAggregate._count.id,
      totalProducts,
      lowStockItemCount: Number(lowStockProducts[0]?.count || 0),
    };
  }

  /**
   * Retrieves list of customers with outstanding balances (*ዕዳ*).
   */
  async getCustomers(shopId: string, search?: string) {
    const where: Prisma.CustomerWhereInput = {
      shopId,
      isDeleted: false,
    };

    if (search) {
      where.OR = [
        { fullName: { contains: search, mode: 'insensitive' } },
        { phoneNumber: { contains: search } },
      ];
    }

    return this.prisma.customer.findMany({
      where,
      orderBy: { totalDebt: 'desc' },
    });
  }

  /**
   * Creates a customer in the shop directory.
   */
  async createCustomer(shopId: string, dto: CreateCustomerDto) {
    return this.prisma.customer.create({
      data: {
        id: randomUUID(),
        shopId,
        fullName: dto.fullName,
        phoneNumber: dto.phoneNumber || null,
        totalDebt: new Prisma.Decimal(0.0),
      },
    });
  }

  /**
   * Retrieves detailed customer credit profile and itemized transaction history:
   * - Customer info & current balance
   * - Itemized credit sales (with items, unit price, quantity)
   * - Repayment records
   */
  async getCustomerLedgerDetails(shopId: string, customerId: string) {
    const customer = await this.prisma.customer.findFirst({
      where: { id: customerId, shopId, isDeleted: false },
    });

    if (!customer) {
      throw new NotFoundException('Customer not found');
    }

    const [creditSales, repayments] = await Promise.all([
      this.prisma.sale.findMany({
        where: { shopId, customerId },
        include: { items: true },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.debtRepayment.findMany({
        where: { shopId, customerId },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    return {
      customer: {
        id: customer.id,
        fullName: customer.fullName,
        phoneNumber: customer.phoneNumber,
        totalDebt: Number(customer.totalDebt),
        updatedAt: customer.updatedAt,
      },
      creditSales: creditSales.map((sale) => ({
        id: sale.id,
        paymentType: sale.paymentType,
        subtotal: Number(sale.subtotal),
        discount: Number(sale.discount),
        grandTotal: Number(sale.grandTotal),
        amountPaid: Number(sale.amountPaid),
        amountDue: Number(sale.amountDue),
        createdAt: sale.createdAt,
        items: sale.items.map((item) => ({
          id: item.id,
          productId: item.productId,
          productName: item.productName,
          unitPrice: Number(item.unitPrice),
          quantity: Number(item.quantity),
          totalPrice: Number(item.totalPrice),
        })),
      })),
      repayments: repayments.map((repayment) => ({
        id: repayment.id,
        amount: Number(repayment.amount),
        paymentMethod: repayment.paymentMethod,
        note: repayment.note,
        createdAt: repayment.createdAt,
      })),
    };
  }

  /**
   * Records a repayment directly in the cloud (e.g. from web or manager portal).
   */
  async recordRepayment(
    shopId: string,
    customerId: string,
    dto: RecordCloudRepaymentDto,
  ) {
    const customer = await this.prisma.customer.findFirst({
      where: { id: customerId, shopId, isDeleted: false },
    });

    if (!customer) {
      throw new NotFoundException('Customer not found');
    }

    return this.prisma.$transaction(async (tx) => {
      const repayment = await tx.debtRepayment.create({
        data: {
          id: randomUUID(),
          shopId,
          customerId,
          amount: new Prisma.Decimal(dto.amount),
          paymentMethod: dto.paymentMethod || 'cash',
          note: dto.note || null,
        },
      });

      // Recalculate customer total debt
      const creditSales = await tx.sale.aggregate({
        where: { shopId, customerId },
        _sum: { amountDue: true },
      });
      const allRepayments = await tx.debtRepayment.aggregate({
        where: { shopId, customerId },
        _sum: { amount: true },
      });

      const totalCredit = creditSales._sum.amountDue
        ? Number(creditSales._sum.amountDue)
        : 0;
      const totalRepaid = allRepayments._sum.amount
        ? Number(allRepayments._sum.amount)
        : 0;
      const newDebt = Math.max(0, totalCredit - totalRepaid);

      const updatedCustomer = await tx.customer.update({
        where: { id: customerId },
        data: { totalDebt: new Prisma.Decimal(newDebt) },
      });

      return {
        repayment: {
          id: repayment.id,
          amount: Number(repayment.amount),
          paymentMethod: repayment.paymentMethod,
          createdAt: repayment.createdAt,
        },
        newBalance: Number(updatedCustomer.totalDebt),
      };
    });
  }

  /**
   * Retrieves products for the shop with low-stock filtering support.
   */
  async getProducts(shopId: string, lowStockOnly = false) {
    if (lowStockOnly) {
      return this.prisma.$queryRaw<any[]>`
        SELECT *
        FROM products
        WHERE shop_id = ${shopId}
          AND is_deleted = false
          AND stock_quantity <= min_stock_level
        ORDER BY name_en ASC
      `;
    }

    return this.prisma.product.findMany({
      where: { shopId, isDeleted: false },
      orderBy: { nameEn: 'asc' },
    });
  }
}
