import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'crypto';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

const uuidv4 = () => randomUUID();

describe('Backend Edge-Cases & Security Hardening E2E (Sub-Phase 5.2)', () => {
  let app: INestApplication;
  let prisma: PrismaService;

  let tokenShopA: string;
  let shopAId: string;

  let tokenShopB: string;
  let shopBId: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    await app.init();

    prisma = app.get(PrismaService);

    // Register Shop A
    const suffixA = Date.now().toString().slice(-5) + '_a';
    const regA = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        shopName: `Edge Shop A ${suffixA}`,
        username: `edge_user_${suffixA}`,
        password: 'password123',
      })
      .expect(201);
    tokenShopA = regA.body.accessToken;
    shopAId = regA.body.shop.id;

    // Register Shop B
    const suffixB = Date.now().toString().slice(-5) + '_b';
    const regB = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        shopName: `Edge Shop B ${suffixB}`,
        username: `edge_user_${suffixB}`,
        password: 'password123',
      })
      .expect(201);
    tokenShopB = regB.body.accessToken;
    shopBId = regB.body.shop.id;
  }, 30000);

  afterAll(async () => {
    // Teardown test shops
    for (const sId of [shopAId, shopBId]) {
      if (sId) {
        await prisma.processedMutation.deleteMany({ where: { shopId: sId } });
        await prisma.debtRepayment.deleteMany({ where: { shopId: sId } });
        await prisma.saleItem.deleteMany({ where: { sale: { shopId: sId } } });
        await prisma.sale.deleteMany({ where: { shopId: sId } });
        await prisma.product.deleteMany({ where: { shopId: sId } });
        await prisma.customer.deleteMany({ where: { shopId: sId } });
        await prisma.user.deleteMany({ where: { shopId: sId } });
        await prisma.shop.deleteMany({ where: { id: sId } });
      }
    }
    await app.close();
  });

  describe('1. Multi-Tenant Isolation & Cross-Shop Security Guards', () => {
    it('should reject push request when shop_id in body does not match authenticated JWT token', async () => {
      // Shop A attempts to push data posing as Shop B
      const crossShopPayload = {
        shop_id: shopBId, // Mismatched!
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 1,
            entity_type: 'product',
            operation: 'CREATE',
            entity_id: uuidv4(),
            data: {
              id: uuidv4(),
              name_en: 'Illicit Product',
              name_am: 'የተከለከለ ዕቃ',
              selling_price: 100.0,
            },
          },
        ],
      };

      const response = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send(crossShopPayload)
        .expect(400);

      expect(response.body.message).toContain('Shop ID in payload does not match authenticated shop');
    });

    it('should strictly isolate pull data between tenants', async () => {
      // Seed a private product in Shop B
      const secretProdId = uuidv4();
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopB}`)
        .send({
          shop_id: shopBId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 1,
              entity_type: 'product',
              operation: 'CREATE',
              entity_id: secretProdId,
              data: {
                id: secretProdId,
                name_en: 'Shop B Secret Item',
                name_am: 'የመደብር ቢ ሚስጥር',
                selling_price: 999.0,
              },
            },
          ],
        })
        .expect(200);

      // Shop A pulls updates
      const pullResponseA = await request(app.getHttpServer())
        .get('/api/v1/sync/pull')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .expect(200);

      // Assert Shop A CANNOT see Shop B's product
      const foundInShopA = pullResponseA.body.data.products.some((p: any) => p.id === secretProdId);
      expect(foundInShopA).toBe(false);

      // Shop B pulls updates and sees its product
      const pullResponseB = await request(app.getHttpServer())
        .get('/api/v1/sync/pull')
        .set('Authorization', `Bearer ${tokenShopB}`)
        .expect(200);

      const foundInShopB = pullResponseB.body.data.products.some((p: any) => p.id === secretProdId);
      expect(foundInShopB).toBe(true);
    });
  });

  describe('2. DTO Validation & Malformed Payload Handling', () => {
    it('should reject push payload with invalid entity_id UUID at DTO validation level', async () => {
      const invalidUuidPayload = {
        shop_id: shopAId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 10,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: 'not-a-valid-uuid-format',
            data: {},
          },
        ],
      };

      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send(invalidUuidPayload)
        .expect(400);
    });

    it('should report FAILED mutation when unsupported payment type is submitted', async () => {
      const invalidPayload = {
        shop_id: shopAId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 11,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: uuidv4(),
            data: {
              id: uuidv4(),
              payment_type: 'bitcoin', // Invalid payment type!
              subtotal: 100.0,
              grand_total: 100.0,
              amount_paid: 100.0,
              amount_due: 0.0,
              created_at: new Date().toISOString(),
              items: [],
            },
          },
        ],
      };

      const response = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send(invalidPayload)
        .expect(200);

      expect(response.body.results[0].status).toBe('FAILED');
      expect(response.body.results[0].error).toContain('Invalid payment_type');
    });

    it('should reject payload with non-whitelisted rogue fields', async () => {
      const roguePayload = {
        shop_id: shopAId,
        client_timestamp: new Date().toISOString(),
        mutations: [],
        maliciousAdminFlag: true, // Non-whitelisted rogue property
      };

      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send(roguePayload)
        .expect(400);
    });
  });

  describe('3. Partial Batch Fault Tolerance', () => {
    it('should process valid mutations while gracefully reporting failed ones in the same batch', async () => {
      const validProdId1 = uuidv4();
      const validProdId2 = uuidv4();

      const batchPayload = {
        shop_id: shopAId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          // 1. Valid Product
          {
            sync_id: 501,
            entity_type: 'product',
            operation: 'CREATE',
            entity_id: validProdId1,
            data: {
              id: validProdId1,
              name_en: 'Valid Bread 1',
              name_am: 'ትክክለኛ ዳቦ 1',
              selling_price: 25.0,
            },
          },
          // 2. Faulty Mutation (Malformed sale date that fails database insertion)
          {
            sync_id: 502,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: uuidv4(),
            data: {
              id: uuidv4(),
              payment_type: 'cash',
              subtotal: 100.0,
              grand_total: 100.0,
              amount_paid: 100.0,
              amount_due: 0.0,
              created_at: 'invalid-date-format',
            },
          },
          // 3. Valid Product
          {
            sync_id: 503,
            entity_type: 'product',
            operation: 'CREATE',
            entity_id: validProdId2,
            data: {
              id: validProdId2,
              name_en: 'Valid Bread 2',
              name_am: 'ትክክለኛ ዳቦ 2',
              selling_price: 30.0,
            },
          },
        ],
      };

      const response = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send(batchPayload)
        .expect(200);

      expect(response.body.status).toBe('success');
      expect(response.body.results).toHaveLength(3);

      // Item 1: SUCCESS
      expect(response.body.results[0].sync_id).toBe(501);
      expect(response.body.results[0].status).toBe('SUCCESS');

      // Item 2: FAILED with descriptive error
      expect(response.body.results[1].sync_id).toBe(502);
      expect(response.body.results[1].status).toBe('FAILED');
      expect(response.body.results[1].error).toBeDefined();

      // Item 3: SUCCESS (Did not crash because item 2 failed)
      expect(response.body.results[2].sync_id).toBe(503);
      expect(response.body.results[2].status).toBe('SUCCESS');

      // Verify valid products exist in PostgreSQL
      const prod1 = await prisma.product.findUnique({ where: { id: validProdId1 } });
      const prod2 = await prisma.product.findUnique({ where: { id: validProdId2 } });
      expect(prod1).not.toBeNull();
      expect(prod2).not.toBeNull();
    });
  });

  describe('4. Dynamic Ledger Interleaving & Clamping Edge Cases', () => {
    const customerId = uuidv4();

    beforeAll(async () => {
      // Create customer with 0 debt
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send({
          shop_id: shopAId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 601,
              entity_type: 'customer',
              operation: 'CREATE',
              entity_id: customerId,
              data: {
                id: customerId,
                full_name: 'Solomon Bogale',
                phone_number: '0911778899',
              },
            },
          ],
        })
        .expect(200);
    });

    it('should prevent debt balance from becoming negative upon overpayment', async () => {
      // Overpayment: customer with 0 debt pays 150 ETB
      const overpaymentId = uuidv4();
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send({
          shop_id: shopAId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 602,
              entity_type: 'debt_repayment',
              operation: 'CREATE',
              entity_id: overpaymentId,
              data: {
                id: overpaymentId,
                customer_id: customerId,
                amount: 150.0,
                payment_method: 'telebirr',
                note: 'Advance payment',
                created_at: new Date().toISOString(),
              },
            },
          ],
        })
        .expect(200);

      // Customer debt must clamp to 0.00 (not -150.00)
      const customer = await prisma.customer.findUnique({ where: { id: customerId } });
      expect(Number(customer!.totalDebt)).toBe(0);
    });

    it('should maintain exact balance through complex interleaved sales and repayments', async () => {
      // Interleaved sequence:
      // 1. Credit sale: 500 ETB
      // 2. Repayment: 200 ETB (expected balance: 300)
      // 3. Credit sale: 450 ETB (expected balance: 750)
      // 4. Repayment: 750 ETB (expected balance: 0)
      const sale1Id = uuidv4();
      const rep1Id = uuidv4();
      const sale2Id = uuidv4();
      const rep2Id = uuidv4();

      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send({
          shop_id: shopAId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 701,
              entity_type: 'sale',
              operation: 'CREATE',
              entity_id: sale1Id,
              data: {
                id: sale1Id,
                customer_id: customerId,
                payment_type: 'credit',
                subtotal: 500.0,
                grand_total: 500.0,
                amount_paid: 0.0,
                amount_due: 500.0,
                created_at: new Date().toISOString(),
                items: [],
              },
            },
            {
              sync_id: 702,
              entity_type: 'debt_repayment',
              operation: 'CREATE',
              entity_id: rep1Id,
              data: {
                id: rep1Id,
                customer_id: customerId,
                amount: 200.0,
                created_at: new Date().toISOString(),
              },
            },
            {
              sync_id: 703,
              entity_type: 'sale',
              operation: 'CREATE',
              entity_id: sale2Id,
              data: {
                id: sale2Id,
                customer_id: customerId,
                payment_type: 'credit',
                subtotal: 450.0,
                grand_total: 450.0,
                amount_paid: 0.0,
                amount_due: 450.0,
                created_at: new Date().toISOString(),
                items: [],
              },
            },
            {
              sync_id: 704,
              entity_type: 'debt_repayment',
              operation: 'CREATE',
              entity_id: rep2Id,
              data: {
                id: rep2Id,
                customer_id: customerId,
                amount: 750.0,
                created_at: new Date().toISOString(),
              },
            },
          ],
        })
        .expect(200);

      // Total Credit: 500 + 450 = 950
      // Total Repaid: 150 (earlier) + 200 + 750 = 1100
      // Clamped Balance: max(0, 950 - 1100) = 0
      const customer = await prisma.customer.findUnique({ where: { id: customerId } });
      expect(Number(customer!.totalDebt)).toBe(0);

      // Now add a new credit sale of 320 ETB
      const newSaleId = uuidv4();
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${tokenShopA}`)
        .send({
          shop_id: shopAId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 705,
              entity_type: 'sale',
              operation: 'CREATE',
              entity_id: newSaleId,
              data: {
                id: newSaleId,
                customer_id: customerId,
                payment_type: 'credit',
                subtotal: 320.0,
                grand_total: 320.0,
                amount_paid: 0.0,
                amount_due: 320.0,
                created_at: new Date().toISOString(),
                items: [],
              },
            },
          ],
        })
        .expect(200);

      const customerUpdated = await prisma.customer.findUnique({ where: { id: customerId } });
      // Total Credit: 950 + 320 = 1270
      // Total Repaid: 1100
      // Balance: 1270 - 1100 = 170.00 ETB
      expect(Number(customerUpdated!.totalDebt)).toBe(170);
    });
  });
});
