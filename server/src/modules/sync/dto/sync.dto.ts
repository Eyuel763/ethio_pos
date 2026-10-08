import { Type } from 'class-transformer';
import {
  IsArray,
  IsEnum,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  ValidateNested,
} from 'class-validator';

export enum SyncOperation {
  CREATE = 'CREATE',
  UPDATE = 'UPDATE',
  DELETE = 'DELETE',
}

export enum EntityType {
  PRODUCT = 'product',
  CUSTOMER = 'customer',
  SALE = 'sale',
  DEBT_REPAYMENT = 'debt_repayment',
}

export class SaleItemPayloadDto {
  @IsUUID()
  id!: string;

  @IsUUID()
  product_id!: string;

  @IsString()
  @IsNotEmpty()
  product_name!: string;

  @IsNumber()
  unit_price!: number;

  @IsNumber()
  quantity!: number;

  @IsNumber()
  total_price!: number;
}

export class SalePayloadDto {
  @IsUUID()
  id!: string;

  @IsOptional()
  @IsUUID()
  customer_id?: string;

  @IsIn(['cash', 'mobile_transfer', 'credit'])
  payment_type!: string;

  @IsNumber()
  subtotal!: number;

  @IsOptional()
  @IsNumber()
  discount?: number;

  @IsNumber()
  grand_total!: number;

  @IsNumber()
  amount_paid!: number;

  @IsNumber()
  amount_due!: number;

  @IsString()
  created_at!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SaleItemPayloadDto)
  items!: SaleItemPayloadDto[];
}

export class ProductPayloadDto {
  @IsUUID()
  id!: string;

  @IsOptional()
  @IsString()
  barcode?: string;

  @IsString()
  @IsNotEmpty()
  name_am!: string;

  @IsString()
  @IsNotEmpty()
  name_en!: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsString()
  unit_type?: string;

  @IsNumber()
  selling_price!: number;

  @IsOptional()
  @IsNumber()
  cost_price?: number;

  @IsOptional()
  @IsNumber()
  stock_quantity?: number;

  @IsOptional()
  @IsNumber()
  min_stock_level?: number;

  @IsOptional()
  is_deleted?: boolean;
}

export class CustomerPayloadDto {
  @IsUUID()
  id!: string;

  @IsString()
  @IsNotEmpty()
  full_name!: string;

  @IsOptional()
  @IsString()
  phone_number?: string;

  @IsOptional()
  @IsNumber()
  total_debt?: number;

  @IsOptional()
  is_deleted?: boolean;
}

export class DebtRepaymentPayloadDto {
  @IsUUID()
  id!: string;

  @IsUUID()
  customer_id!: string;

  @IsNumber()
  amount!: number;

  @IsOptional()
  @IsString()
  payment_method?: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsString()
  created_at!: string;
}

export class MutationDto {
  @IsInt()
  sync_id!: number;

  @IsEnum(EntityType)
  entity_type!: EntityType;

  @IsEnum(SyncOperation)
  operation!: SyncOperation;

  @IsUUID()
  entity_id!: string;

  @IsNotEmpty()
  data!: any;
}

export class SyncPushDto {
  @IsUUID()
  shop_id!: string;

  @IsString()
  client_timestamp!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MutationDto)
  mutations!: MutationDto[];
}

export class SyncResultItemDto {
  sync_id!: number;
  status!: 'SUCCESS' | 'FAILED';
  entity_id!: string;
  error?: string;
}

export class SyncPushResponseDto {
  status!: string;
  processed_at!: string;
  results!: SyncResultItemDto[];
}
