import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { randomUUID } from 'crypto';
const uuidv4 = () => randomUUID();
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

describe('Sync Engine & Conflict Resolution E2E (Sub-Phase 5.1)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let authToken: string;
  let shopId: string;

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

    // Register a unique test shop for isolation
    const uniqueSuffix = Date.now().toString().slice(-6);
    const registerResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/register')
      .send({
        shopName: `E2E Test Shop ${uniqueSuffix}`,
        username: `e2e_user_${uniqueSuffix}`,
        password: 'password123',
        fullName: 'E2E Test Operator',
        phoneNumber: '+251911000000',
      })
      .expect(201);

    authToken = registerResponse.body.accessToken;
    shopId = registerResponse.body.shop.id;
    expect(authToken).toBeDefined();
    expect(shopId).toBeDefined();
  }, 30000);

  afterAll(async () => {
    // Clean up test data created for this shop
    if (shopId) {
      await prisma.processedMutation.deleteMany({ where: { shopId } });
      await prisma.debtRepayment.deleteMany({ where: { shopId } });
      await prisma.saleItem.deleteMany({ where: { sale: { shopId } } });
      await prisma.sale.deleteMany({ where: { shopId } });
      await prisma.product.deleteMany({ where: { shopId } });
      await prisma.customer.deleteMany({ where: { shopId } });
      await prisma.user.deleteMany({ where: { shopId } });
      await prisma.shop.deleteMany({ where: { id: shopId } });
    }
    await app.close();
  });

  describe('5.1.1 Full Lifecycle Offline-to-Online Flow', () => {
    const productId = uuidv4();
    const customerId = uuidv4();
    const saleId = uuidv4();
    const saleItemId = uuidv4();
    const repaymentId = uuidv4();

    it('should push a batch of offline mutations and atomically reflect all entities and stock in PostgreSQL', async () => {
      const pushPayload = {
        shop_id: shopId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          // 1. Product creation offline with 50 units
          {
            sync_id: 1,
            entity_type: 'product',
            operation: 'CREATE',
            entity_id: productId,
            data: {
              id: productId,
              name_en: 'Sun Flower Oil 5L',
              name_am: 'የሱፍ ዘይት 5 ሊትር',
              category: 'Groceries',
              unit_type: 'piece',
              selling_price: 450.0,
              cost_price: 380.0,
              stock_quantity: 50.0,
              min_stock_level: 5.0,
            },
          },
          // 2. Customer profile creation offline
          {
            sync_id: 2,
            entity_type: 'customer',
            operation: 'CREATE',
            entity_id: customerId,
            data: {
              id: customerId,
              full_name: 'Kebede Balcha',
              phone_number: '0911223344',
            },
          },
          // 3. Partial Credit Sale: 2 units sold (Total: 900 ETB, Paid: 300 ETB, Credit Debt: 600 ETB)
          {
            sync_id: 3,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: saleId,
            data: {
              id: saleId,
              customer_id: customerId,
              payment_type: 'credit',
              subtotal: 900.0,
              discount: 0.0,
              grand_total: 900.0,
              amount_paid: 300.0,
              amount_due: 600.0,
              created_at: new Date().toISOString(),
              items: [
                {
                  id: saleItemId,
                  product_id: productId,
                  product_name: 'Sun Flower Oil 5L',
                  unit_price: 450.0,
                  quantity: 2.0,
                  total_price: 900.0,
                },
              ],
            },
          },
          // 4. Repayment logged offline: 200 ETB paid back via Telebirr
          {
            sync_id: 4,
            entity_type: 'debt_repayment',
            operation: 'CREATE',
            entity_id: repaymentId,
            data: {
              id: repaymentId,
              customer_id: customerId,
              amount: 200.0,
              payment_method: 'telebirr',
              note: 'Telebirr Ref #TB998877',
              created_at: new Date().toISOString(),
            },
          },
          // 5. Stock adjustment offline: Received new shipment of +15 units
          {
            sync_id: 5,
            entity_type: 'product',
            operation: 'UPDATE',
            entity_id: productId,
            data: {
              id: productId,
              stock_delta: 15.0,
            },
          },
        ],
      };

      const response = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${authToken}`)
        .send(pushPayload)
        .expect(200);

      expect(response.body.status).toBe('success');
      expect(response.body.results).toHaveLength(5);
      response.body.results.forEach((res: any) => {
        expect(res.status).toBe('SUCCESS');
      });

      // Assert PostgreSQL Database State
      // Stock = Initial(50) - Sold(2) + Adjustment(15) = 63
      const productInDb = await prisma.product.findUnique({ where: { id: productId } });
      expect(productInDb).not.toBeNull();
      expect(Number(productInDb!.stockQuantity)).toBe(63);

      // Customer Total Debt = Credit sale(600) - Repayment(200) = 400
      const customerInDb = await prisma.customer.findUnique({ where: { id: customerId } });
      expect(customerInDb).not.toBeNull();
      expect(Number(customerInDb!.totalDebt)).toBe(400);

      // Verify Sale Header and Items
      const saleInDb = await prisma.sale.findUnique({
        where: { id: saleId },
        include: { items: true },
      });
      expect(saleInDb).not.toBeNull();
      expect(Number(saleInDb!.grandTotal)).toBe(900);
      expect(Number(saleInDb!.amountPaid)).toBe(300);
      expect(Number(saleInDb!.amountDue)).toBe(600);
      expect(saleInDb!.items).toHaveLength(1);
      expect(Number(saleInDb!.items[0].quantity)).toBe(2);

      // Verify Repayment record
      const repaymentInDb = await prisma.debtRepayment.findUnique({ where: { id: repaymentId } });
      expect(repaymentInDb).not.toBeNull();
      expect(Number(repaymentInDb!.amount)).toBe(200);
      expect(repaymentInDb!.paymentMethod).toBe('telebirr');
    });

    it('should allow pulling all updated records via GET /api/v1/sync/pull', async () => {
      const pullResponse = await request(app.getHttpServer())
        .get('/api/v1/sync/pull')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(pullResponse.body.server_timestamp).toBeDefined();
      expect(pullResponse.body.data).toBeDefined();
      expect(pullResponse.body.data.products.some((p: any) => p.id === productId)).toBe(true);
      expect(pullResponse.body.data.customers.some((c: any) => c.id === customerId)).toBe(true);
    });
  });

  describe('5.1.2 Concurrent Device Conflict Simulation (Delta Stock Calculations)', () => {
    const concurrentProductId = uuidv4();

    beforeAll(async () => {
      // Create product with baseline stock = 100 units
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          shop_id: shopId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 10,
              entity_type: 'product',
              operation: 'CREATE',
              entity_id: concurrentProductId,
              data: {
                id: concurrentProductId,
                name_en: 'Coca Cola 500ml',
                name_am: 'ኮካ ኮላ 500ሚሊ',
                selling_price: 40.0,
                stock_quantity: 100.0,
              },
            },
          ],
        })
        .expect(200);
    });

    it('should preserve accurate stock counts when multiple offline devices submit sales concurrently', async () => {
      // Device A sells 7 units offline
      const saleAId = uuidv4();
      const payloadDeviceA = {
        shop_id: shopId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 101,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: saleAId,
            data: {
              id: saleAId,
              payment_type: 'cash',
              subtotal: 280.0,
              discount: 0.0,
              grand_total: 280.0,
              amount_paid: 280.0,
              amount_due: 0.0,
              created_at: new Date().toISOString(),
              items: [
                {
                  id: uuidv4(),
                  product_id: concurrentProductId,
                  product_name: 'Coca Cola 500ml',
                  unit_price: 40.0,
                  quantity: 7.0,
                  total_price: 280.0,
                },
              ],
            },
          },
        ],
      };

      // Device B sells 13 units offline
      const saleBId = uuidv4();
      const payloadDeviceB = {
        shop_id: shopId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 201,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: saleBId,
            data: {
              id: saleBId,
              payment_type: 'cash',
              subtotal: 520.0,
              discount: 0.0,
              grand_total: 520.0,
              amount_paid: 520.0,
              amount_due: 0.0,
              created_at: new Date().toISOString(),
              items: [
                {
                  id: uuidv4(),
                  product_id: concurrentProductId,
                  product_name: 'Coca Cola 500ml',
                  unit_price: 40.0,
                  quantity: 13.0,
                  total_price: 520.0,
                },
              ],
            },
          },
        ],
      };

      // Both devices push mutations to the server (simulating concurrent reconnects)
      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post('/api/v1/sync/push')
          .set('Authorization', `Bearer ${authToken}`)
          .send(payloadDeviceA),
        request(app.getHttpServer())
          .post('/api/v1/sync/push')
          .set('Authorization', `Bearer ${authToken}`)
          .send(payloadDeviceB),
      ]);

      expect(resA.status).toBe(200);
      expect(resB.status).toBe(200);
      expect(resA.body.results[0].status).toBe('SUCCESS');
      expect(resB.body.results[0].status).toBe('SUCCESS');

      // Delta arithmetic verification:
      // Initial stock: 100
      // Device A delta: -7
      // Device B delta: -13
      // Final stock MUST be 100 - 7 - 13 = 80 (neither device overwrote the other)
      const updatedProduct = await prisma.product.findUnique({
        where: { id: concurrentProductId },
      });
      expect(Number(updatedProduct!.stockQuantity)).toBe(80);
    });
  });

  describe('5.1.3 Ledger Idempotence & Duplicate Retry Protection', () => {
    const idempotentProductId = uuidv4();
    const idempotentCustomerId = uuidv4();
    const idempotentSaleId = uuidv4();
    const idempotentRepaymentId = uuidv4();

    beforeAll(async () => {
      // Create baseline product & customer
      await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          shop_id: shopId,
          client_timestamp: new Date().toISOString(),
          mutations: [
            {
              sync_id: 301,
              entity_type: 'product',
              operation: 'CREATE',
              entity_id: idempotentProductId,
              data: {
                id: idempotentProductId,
                name_en: 'Sugar 1kg',
                name_am: 'ስኳር 1ኪግ',
                selling_price: 120.0,
                stock_quantity: 40.0,
              },
            },
            {
              sync_id: 302,
              entity_type: 'customer',
              operation: 'CREATE',
              entity_id: idempotentCustomerId,
              data: {
                id: idempotentCustomerId,
                full_name: 'Taye Mekonnen',
                phone_number: '0912345678',
              },
            },
          ],
        })
        .expect(200);
    });

    it('should ignore duplicate push payloads and maintain exact debt and stock balances', async () => {
      const singleSalePayload = {
        shop_id: shopId,
        client_timestamp: new Date().toISOString(),
        mutations: [
          {
            sync_id: 303,
            entity_type: 'sale',
            operation: 'CREATE',
            entity_id: idempotentSaleId,
            data: {
              id: idempotentSaleId,
              customer_id: idempotentCustomerId,
              payment_type: 'credit',
              subtotal: 360.0,
              discount: 0.0,
              grand_total: 360.0,
              amount_paid: 60.0,
              amount_due: 300.0,
              created_at: new Date().toISOString(),
              items: [
                {
                  id: uuidv4(),
                  product_id: idempotentProductId,
                  product_name: 'Sugar 1kg',
                  unit_price: 120.0,
                  quantity: 3.0,
                  total_price: 360.0,
                },
              ],
            },
          },
          {
            sync_id: 304,
            entity_type: 'debt_repayment',
            operation: 'CREATE',
            entity_id: idempotentRepaymentId,
            data: {
              id: idempotentRepaymentId,
              customer_id: idempotentCustomerId,
              amount: 100.0,
              payment_method: 'cash',
              note: 'Partial cash payment',
              created_at: new Date().toISOString(),
            },
          },
        ],
      };

      // First Push: Normal processing
      const firstResponse = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${authToken}`)
        .send(singleSalePayload)
        .expect(200);

      expect(firstResponse.body.results[0].status).toBe('SUCCESS');
      expect(firstResponse.body.results[1].status).toBe('SUCCESS');

      // Verify baseline after first push
      // Stock: 40 - 3 = 37
      const productFirstCheck = await prisma.product.findUnique({ where: { id: idempotentProductId } });
      expect(Number(productFirstCheck!.stockQuantity)).toBe(37);

      // Debt: 300 - 100 = 200
      const customerFirstCheck = await prisma.customer.findUnique({ where: { id: idempotentCustomerId } });
      expect(Number(customerFirstCheck!.totalDebt)).toBe(200);

      // Verify exactly 1 Sale and 1 Repayment exist
      const salesCountFirst = await prisma.sale.count({ where: { id: idempotentSaleId } });
      const repaymentCountFirst = await prisma.debtRepayment.count({ where: { id: idempotentRepaymentId } });
      expect(salesCountFirst).toBe(1);
      expect(repaymentCountFirst).toBe(1);

      // Second Push: Client network retry with the IDENTICAL payload
      const retryResponse = await request(app.getHttpServer())
        .post('/api/v1/sync/push')
        .set('Authorization', `Bearer ${authToken}`)
        .send(singleSalePayload)
        .expect(200);

      expect(retryResponse.body.status).toBe('success');
      expect(retryResponse.body.results[0].status).toBe('SUCCESS');
      expect(retryResponse.body.results[1].status).toBe('SUCCESS');

      // IDEMPOTENCY ASSERTIONS:
      // 1. Stock quantity must STILL be 37 (NOT decremented twice to 34)
      const productSecondCheck = await prisma.product.findUnique({ where: { id: idempotentProductId } });
      expect(Number(productSecondCheck!.stockQuantity)).toBe(37);

      // 2. Customer debt must STILL be 200 (NOT decremented twice or corrupted)
      const customerSecondCheck = await prisma.customer.findUnique({ where: { id: idempotentCustomerId } });
      expect(Number(customerSecondCheck!.totalDebt)).toBe(200);

      // 3. No duplicate records in database
      const salesCountSecond = await prisma.sale.count({ where: { id: idempotentSaleId } });
      const repaymentCountSecond = await prisma.debtRepayment.count({ where: { id: idempotentRepaymentId } });
      expect(salesCountSecond).toBe(1);
      expect(repaymentCountSecond).toBe(1);
    });
  });
});
