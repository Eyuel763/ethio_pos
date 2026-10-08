import { Test, TestingModule } from '@nestjs/testing';
import { SyncService } from './sync.service';
import { PrismaService } from '../../prisma/prisma.service';
import { EntityType, SyncOperation, SyncPushDto } from './dto/sync.dto';
import { BadRequestException } from '@nestjs/common';

describe('SyncService', () => {
  let service: SyncService;
  let prisma: PrismaService;

  const mockPrismaService = {
    processedMutation: {
      findUnique: jest.fn(),
      create: jest.fn(),
    },
    sale: {
      findUnique: jest.fn(),
      create: jest.fn(),
      aggregate: jest.fn(),
    },
    saleItem: {
      create: jest.fn(),
    },
    product: {
      findUnique: jest.fn(),
      update: jest.fn(),
      create: jest.fn(),
      findMany: jest.fn(),
    },
    customer: {
      findUnique: jest.fn(),
      update: jest.fn(),
      findMany: jest.fn(),
    },
    debtRepayment: {
      findUnique: jest.fn(),
      create: jest.fn(),
      aggregate: jest.fn(),
    },
    $transaction: jest.fn((callback) => callback(mockPrismaService)),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SyncService,
        { provide: PrismaService, useValue: mockPrismaService },
      ],
    }).compile();

    service = module.get<SyncService>(SyncService);
    prisma = module.get<PrismaService>(PrismaService);
    jest.clearAllMocks();
  });

  it('should reject push if shop_id does not match authenticated shop', async () => {
    const payload: SyncPushDto = {
      shop_id: 'shop-uuid-A',
      client_timestamp: new Date().toISOString(),
      mutations: [],
    };

    await expect(service.processPush('shop-uuid-B', payload)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('should acknowledge idempotent hit without creating duplicate record', async () => {
    const shopId = 'shop-uuid-1';
    mockPrismaService.processedMutation.findUnique.mockResolvedValue({
      id: 'log-1',
      shopId,
      syncId: 101,
      entityType: 'sale',
      entityId: 'sale-uuid-1',
      operation: 'CREATE',
    });

    const payload: SyncPushDto = {
      shop_id: shopId,
      client_timestamp: new Date().toISOString(),
      mutations: [
        {
          sync_id: 101,
          entity_type: EntityType.SALE,
          operation: SyncOperation.CREATE,
          entity_id: 'sale-uuid-1',
          data: {},
        },
      ],
    };

    const response = await service.processPush(shopId, payload);
    expect(response.status).toBe('success');
    expect(response.results).toHaveLength(1);
    expect(response.results[0].status).toBe('SUCCESS');
    expect(mockPrismaService.sale.create).not.toHaveBeenCalled();
  });

  it('should process a sale and decrement product stock using relative delta', async () => {
    const shopId = 'shop-uuid-1';
    mockPrismaService.processedMutation.findUnique.mockResolvedValue(null);
    mockPrismaService.sale.findUnique.mockResolvedValue(null);
    mockPrismaService.product.findUnique.mockResolvedValue({
      id: 'prod-uuid-1',
      stockQuantity: 10,
    });

    const payload: SyncPushDto = {
      shop_id: shopId,
      client_timestamp: new Date().toISOString(),
      mutations: [
        {
          sync_id: 102,
          entity_type: EntityType.SALE,
          operation: SyncOperation.CREATE,
          entity_id: 'sale-uuid-2',
          data: {
            payment_type: 'cash',
            subtotal: 50,
            grand_total: 50,
            amount_paid: 50,
            amount_due: 0,
            items: [
              {
                id: 'item-uuid-1',
                product_id: 'prod-uuid-1',
                product_name: 'Injera',
                unit_price: 25,
                quantity: 2,
                total_price: 50,
              },
            ],
          },
        },
      ],
    };

    const response = await service.processPush(shopId, payload);
    expect(response.status).toBe('success');
    expect(response.results[0].status).toBe('SUCCESS');
    expect(mockPrismaService.sale.create).toHaveBeenCalled();
    expect(mockPrismaService.product.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'prod-uuid-1' },
        data: expect.objectContaining({
          stockQuantity: expect.objectContaining({
            decrement: expect.anything(),
          }),
        }),
      }),
    );
  });
});
