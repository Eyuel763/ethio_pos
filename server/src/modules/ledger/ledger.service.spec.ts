import { Test, TestingModule } from '@nestjs/testing';
import { LedgerService } from './ledger.service';
import { PrismaService } from '../../prisma/prisma.service';

describe('LedgerService', () => {
  let service: LedgerService;
  let prisma: PrismaService;

  const mockPrismaService = {
    customer: {
      aggregate: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    sale: {
      aggregate: jest.fn(),
      findMany: jest.fn(),
    },
    product: {
      count: jest.fn(),
      findMany: jest.fn(),
    },
    debtRepayment: {
      findMany: jest.fn(),
      create: jest.fn(),
      aggregate: jest.fn(),
    },
    $queryRaw: jest.fn().mockResolvedValue([{ count: 2n }]),
    $transaction: jest.fn((callback) => callback(mockPrismaService)),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LedgerService,
        { provide: PrismaService, useValue: mockPrismaService },
      ],
    }).compile();

    service = module.get<LedgerService>(LedgerService);
    prisma = module.get<PrismaService>(PrismaService);
    jest.clearAllMocks();
  });

  it('should return aggregate shop metrics correctly', async () => {
    mockPrismaService.customer.aggregate.mockResolvedValue({
      _sum: { totalDebt: 1250.5 },
      _count: { id: 8 },
    });
    mockPrismaService.sale.aggregate.mockResolvedValue({
      _sum: { grandTotal: 5400, amountPaid: 4150, amountDue: 1250 },
      _count: { id: 32 },
    });
    mockPrismaService.product.count.mockResolvedValue(45);

    const metrics = await service.getShopOverviewMetrics('shop-uuid-1');

    expect(metrics.totalOutstandingDebt).toBe(1250.5);
    expect(metrics.totalCustomersWithTabs).toBe(8);
    expect(metrics.totalSalesRevenue).toBe(5400);
    expect(metrics.totalCashCollected).toBe(4150);
    expect(metrics.totalProducts).toBe(45);
    expect(metrics.lowStockItemCount).toBe(2);
  });

  it('should retrieve itemized customer debt ledger breakdown', async () => {
    mockPrismaService.customer.findFirst.mockResolvedValue({
      id: 'cust-1',
      fullName: 'Kebede Tadesse',
      phoneNumber: '0911234567',
      totalDebt: 350.0,
      updatedAt: new Date(),
    });

    mockPrismaService.sale.findMany.mockResolvedValue([
      {
        id: 'sale-1',
        paymentType: 'credit',
        subtotal: 450,
        discount: 0,
        grandTotal: 450,
        amountPaid: 100,
        amountDue: 350,
        createdAt: new Date(),
        items: [
          {
            id: 'item-1',
            productId: 'prod-1',
            productName: '5L Cooking Oil',
            unitPrice: 450,
            quantity: 1,
            totalPrice: 450,
          },
        ],
      },
    ]);

    mockPrismaService.debtRepayment.findMany.mockResolvedValue([]);

    const details = await service.getCustomerLedgerDetails('shop-uuid-1', 'cust-1');

    expect(details.customer.fullName).toBe('Kebede Tadesse');
    expect(details.customer.totalDebt).toBe(350.0);
    expect(details.creditSales).toHaveLength(1);
    expect(details.creditSales[0].items[0].productName).toBe('5L Cooking Oil');
  });
});
