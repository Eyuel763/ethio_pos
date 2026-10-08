# Multi-stage Dockerfile for NestJS Backend using Debian-slim for full OpenSSL & native binary compatibility
FROM node:24-slim AS builder

WORKDIR /app

# Install openssl
RUN apt-get update -y && apt-get install -y openssl

# Copy dependency specifications
COPY package*.json ./
COPY prisma ./prisma/

# Install dependencies (including devDependencies for build)
RUN npm ci

# Generate Prisma Client
RUN npx prisma generate

# Copy source code and build
COPY . .
RUN npm run build

# Production stage
FROM node:24-slim AS runner

WORKDIR /app

ENV NODE_ENV=production

# Install openssl in runner
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# Copy built artifacts and production dependencies
COPY package*.json ./
COPY prisma ./prisma/

# Install only production dependencies
RUN npm ci --omit=dev

# Generate Prisma Client for the production node_modules
RUN npx prisma generate

# Copy compiled application from builder
COPY --from=builder /app/dist ./dist

EXPOSE 3001

CMD ["node", "dist/main"]
