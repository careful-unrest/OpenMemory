# OpenMemory Setup Guide

This guide documents how to run OpenMemory backend + dashboard with Docker Compose.

## Quick Start

```bash
cd /home/sim/Documents/Projects/openmemory
docker compose up --build
```

**Services:**
- Backend API: `http://localhost:8080`
- Dashboard: `http://localhost:3001`

## Configuration Files

### 1. Backend Environment (`.env`)

Key settings in the root `.env` file:

```env
# API Authentication (clients must send this key)
OM_API_KEY=secret

# Dashboard URL (browser-accessible backend URL)
DASHBOARD_API_URL=http://localhost:8080

# Embeddings provider (openai, synthetic, ollama, gemini)
OM_EMBEDDINGS=openai
OPENAI_API_KEY=sk-your-key-here

# Performance tier (hybrid, fast, smart, deep)
OM_TIER=smart

# Storage
OM_METADATA_BACKEND=sqlite
OM_DB_PATH=/data/openmemory.sqlite
```

### 2. Dashboard Environment (`dashboard/.env.local`)

```env
NEXT_PUBLIC_API_URL=http://localhost:8080
NEXT_PUBLIC_API_KEY=secret
```

The `NEXT_PUBLIC_API_KEY` must match `OM_API_KEY` in the backend.

## Files Added/Modified for Docker Dashboard

### Created: `dashboard/Dockerfile`

```dockerfile
FROM node:20-alpine AS base

FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_API_KEY
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_KEY=$NEXT_PUBLIC_API_KEY
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
RUN mkdir .next
RUN chown nextjs:nodejs .next
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

### Modified: `dashboard/next.config.ts`

Added `output: 'standalone'` for Docker compatibility:

```typescript
const nextConfig: NextConfig = {
  output: 'standalone',
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'cdn.spectrumdevs.com',
        pathname: '/**',
      },
    ],
  },
};
```

### Modified: `docker-compose.yml`

Added dashboard service and fixed healthcheck:

```yaml
services:
  openmemory:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - '8080:8080'
    environment:
      # ... (all the OM_* variables)
    volumes:
      - openmemory_data:/data
    restart: unless-stopped
    healthcheck:
      # Use node instead of curl (curl not installed in production image)
      test: ['CMD', 'node', '-e', "require('http').get('http://localhost:8080/health', (res) => process.exit(res.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  dashboard:
    build:
      context: ./dashboard
      dockerfile: Dockerfile
      args:
        - NEXT_PUBLIC_API_URL=${DASHBOARD_API_URL:-http://localhost:8080}
        - NEXT_PUBLIC_API_KEY=${OM_API_KEY:-}
    ports:
      - '3001:3000'  # 3001 because main app uses 3000
    environment:
      - NEXT_PUBLIC_API_URL=${DASHBOARD_API_URL:-http://localhost:8080}
      - NEXT_PUBLIC_API_KEY=${OM_API_KEY:-}
    depends_on:
      openmemory:
        condition: service_healthy
    restart: unless-stopped

volumes:
  openmemory_data:
    driver: local
```

## Mastra Chat App Integration

### Environment Variables (`.env`)

```env
OPENMEMORY_URL=http://localhost:8080
OPENMEMORY_API_KEY=secret
```

### Code Change (`mastra/shared.ts`)

Changed from local SQLite to remote API:

```typescript
// Before (local mode)
new OpenMemory({
  mode: "local",
  path: "./data/openmemory.sqlite",
  tier: "smart",
  embeddings: {
    provider: "openai",
    apiKey: process.env.OPENAI_API_KEY!,
  },
})

// After (remote mode)
new OpenMemory({
  mode: "remote",
  url: process.env.OPENMEMORY_URL || "http://localhost:8080",
  apiKey: process.env.OPENMEMORY_API_KEY,
})
```

### API Response Format Handling

The remote API returns different formats than the local SDK. Updated code handles both:

```typescript
// getAll() response
const response = await om.getAll({ limit: 500 });
const memories = Array.isArray(response)
  ? response
  : response?.memories ?? response?.data ?? [];

// query() response
const response = await om.query(searchQuery, { k: 5 });
const memories = Array.isArray(response)
  ? response
  : response?.matches ?? response?.results ?? [];
```

## Troubleshooting

### "API key required" error
- Ensure `OM_API_KEY` in backend `.env` matches `NEXT_PUBLIC_API_KEY` in `dashboard/.env.local`
- Ensure `OPENMEMORY_API_KEY` in mastra app matches `OM_API_KEY`

### Dashboard won't start (unhealthy backend)
- The original healthcheck used `curl` which isn't installed in the production image
- Fixed by using Node.js for healthcheck instead

### Port conflicts
- Dashboard runs on 3001 (not 3000) to avoid conflict with main Next.js app
- Backend runs on 8080

### Package lock out of sync
- Dashboard Dockerfile uses `npm install` instead of `npm ci` to handle lock file mismatches

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/memory/add` | POST | Add a memory |
| `/memory/query` | POST | Query memories semantically |
| `/memory/all` | GET | List all memories |
| `/memory/:id` | GET | Get single memory |
| `/memory/:id` | PATCH | Update memory |
| `/memory/:id` | DELETE | Delete memory |
