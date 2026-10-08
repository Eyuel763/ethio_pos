import { Test, TestingModule } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { PrismaService } from '../../prisma/prisma.service';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';

describe('AuthService', () => {
  let service: AuthService;
  let prisma: PrismaService;
  let jwt: JwtService;

  const mockPrismaService = {
    user: {
      findUnique: jest.fn(),
      create: jest.fn(),
    },
    shop: {
      create: jest.fn(),
    },
    $transaction: jest.fn(),
  };

  const mockJwtService = {
    sign: jest.fn().mockReturnValue('mock_jwt_token'),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: JwtService, useValue: mockJwtService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
    prisma = module.get<PrismaService>(PrismaService);
    jwt = module.get<JwtService>(JwtService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('login', () => {
    it('should authenticate user and return token with shopId', async () => {
      const plainPassword = 'password123';
      const passwordHash = await bcrypt.hash(plainPassword, 10);

      mockPrismaService.user.findUnique.mockResolvedValue({
        id: 'user-uuid-1',
        username: 'operator1',
        passwordHash,
        role: 'operator',
        shopId: 'shop-uuid-1',
        shop: {
          id: 'shop-uuid-1',
          name: 'Bole Mini Market',
        },
      });

      const result = await service.login({
        username: 'operator1',
        password: plainPassword,
      });

      expect(result).toHaveProperty('accessToken', 'mock_jwt_token');
      expect(result.shop.id).toBe('shop-uuid-1');
      expect(result.user.username).toBe('operator1');
    });

    it('should throw UnauthorizedException if password does not match', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue({
        id: 'user-uuid-1',
        username: 'operator1',
        passwordHash: 'wronghash',
        shopId: 'shop-uuid-1',
      });

      await expect(
        service.login({
          username: 'operator1',
          password: 'wrongpassword',
        }),
      ).rejects.toThrow('Invalid credentials');
    });
  });
});
