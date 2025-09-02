# trade-godz-journal
“AI-powered futures trading journal with Zorian coaching &amp; analytics.”
# TradeGodz Journal

AI-powered futures trading journal with Zorian coaching, ATR-aware analytics, and fast import/export.

## Tech Stack
- **API**: NestJS + Prisma + PostgreSQL
- **Web**: Next.js + React + TailwindCSS
- **Auth**: JWT (API), NextAuth (optional for Web)
- **CI**: GitHub Actions (lint, typecheck, test)
- **Pkg mgmt**: pnpm (monorepo)

## Quickstart

```bash
# 1) clone
git clone https://github.com/westtommy63-commits/TradeGodz-Journal.git
cd TradeGodz-Journal

# 2) enable workspace
pnpm install

# 3) env
cp .env.example .env

# 4) dev db (Docker)
docker run --name tgz-db -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=tgz \
  -p 5432:5432 -d postgres:16

# 5) migrate + seed
cd apps/api
pnpm prisma migrate dev
pnpm ts-node prisma/seed.ts
pnpm start:dev

# 6) web
cd ../web
pnpm dev
