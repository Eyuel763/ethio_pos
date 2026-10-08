import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../prisma/prisma.service';
import { LoginDto, RegisterShopDto } from './dto/auth.dto';
import { JwtPayload } from './interfaces/jwt-payload.interface';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  async registerShop(dto: RegisterShopDto) {
    const existingUser = await this.prisma.user.findUnique({
      where: { username: dto.username },
    });
    if (existingUser) {
      throw new ConflictException('Username already registered');
    }

    const saltRounds = 10;
    const passwordHash = await bcrypt.hash(dto.password, saltRounds);

    // Create Shop and User in a transaction
    const result = await this.prisma.$transaction(async (tx) => {
      const shop = await tx.shop.create({
        data: {
          name: dto.shopName,
          ownerName: dto.fullName,
          phoneNumber: dto.phoneNumber,
        },
      });

      const user = await tx.user.create({
        data: {
          shopId: shop.id,
          username: dto.username,
          passwordHash,
          fullName: dto.fullName,
          role: 'admin',
        },
      });

      return { shop, user };
    });

    const payload: JwtPayload = {
      sub: result.user.id,
      username: result.user.username,
      shopId: result.shop.id,
      role: result.user.role,
    };

    return {
      accessToken: this.jwtService.sign(payload),
      shop: {
        id: result.shop.id,
        name: result.shop.name,
      },
      user: {
        id: result.user.id,
        username: result.user.username,
        role: result.user.role,
      },
    };
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({
      where: { username: dto.username },
      include: { shop: true },
    });

    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const isMatch = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isMatch) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const payload: JwtPayload = {
      sub: user.id,
      username: user.username,
      shopId: user.shopId,
      role: user.role,
    };

    return {
      accessToken: this.jwtService.sign(payload),
      shop: {
        id: user.shop.id,
        name: user.shop.name,
      },
      user: {
        id: user.id,
        username: user.username,
        role: user.role,
      },
    };
  }

  async getMe(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { shop: true },
    });
    if (!user) {
      throw new BadRequestException('User not found');
    }
    return {
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      role: user.role,
      shop: {
        id: user.shop.id,
        name: user.shop.name,
        ownerName: user.shop.ownerName,
        phoneNumber: user.shop.phoneNumber,
      },
    };
  }
}
