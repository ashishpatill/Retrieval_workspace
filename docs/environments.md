# Environment management — Production vs Sandbox

This meta-repo runs **BIMWeb** (Next.js on Vercel + Neon) and **bimrag-backend** services (local Docker or BIMCloud on GCP).

## Overview

| Aspect | Production | Sandbox / Dev |
|--------|------------|---------------|
| Git branch | `main` | feature branches, PRs, local |
| Neon branch | `main` (default) | `dev` |
| Neon project | `bimweb` (`blue-cake-13205477`) | same project, `dev` branch |
| Frontend deploy | Vercel production (`vercel --prod`) | Vercel preview or `pnpm dev` |
| Backend deploy | BIMCloud GCP (Cloud Run + Terraform) | `docker compose up` or `./start-platform.sh` |
| Database URL | Vercel Production env + GitHub secret | `.env.local` / Neon dev branch |
| Auth bypass | **Off** | `E2E_TEST_BYPASS=true` for Playwright only |

## Neon

| Branch | Branch ID | Use |
|--------|-----------|-----|
| `main` | `br-gentle-cloud-atsvon99` | Production (`DATABASE_URL` on Vercel + GitHub Actions) |
| `dev` | `br-rapid-union-atj3wffr` | Local dev, sandbox, CI E2E against dev data |

**Project ID:** `blue-cake-13205477`  
**Org ID:** `org-silent-sea-32809504`

Last reconnect check (2026-07-08): both branches `ready`; main has migration `0002_narrow_lady_ursula` tables (`workspaces`, `api_keys`, `audit_logs`, `documents`, `notification_preferences`, `search_history`).

Migrations live in `BIMWeb/src/db/migrations/`. Apply with:

```bash
cd BIMWeb
pnpm db:migrate          # uses .env.local (dev branch)
pnpm db:check            # verify migration 0002 markers
```

For production Neon (`main` branch), use a local-only file (never commit):

```bash
cp .env.sandbox.example .env.production.local
# set DATABASE_URL to main-branch connection string
ENV=production pnpm db:migrate
```

## Vercel

| Setting | Value |
|---------|-------|
| Team | Ashish P's projects |
| Team ID | `team_CLXPxEDYIpsGkYyu3y2sSWFO` |
| Team slug | `ashish-ps-projects-a6122913` |
| Project | `bimweb` |
| Project ID | `prj_MKPAZVkmOqAbkqzVUKT23XgiFPt8` |
| Production URL | Not live — builds fail (see blockers below) |
| Preview URL (latest) | `https://bimweb-hhigt4c0m-ashish-ps-projects-a6122913.vercel.app` (ERROR) |
| Project aliases | `bimweb-ashish-ps-projects-a6122913.vercel.app` |

**GitHub secrets (BIMWeb repo):**

- `VERCEL_TOKEN` — personal/team token from Vercel dashboard
- `VERCEL_ORG_ID` — `team_CLXPxEDYIpsGkYyu3y2sSWFO`
- `VERCEL_PROJECT_ID` — `prj_MKPAZVkmOqAbkqzVUKT23XgiFPt8`
- `DATABASE_URL` — Neon **main** branch connection string

**GitHub secrets (Retrieval_workspace meta-repo):**

- `DATABASE_URL` — Neon dev or main (E2E uses bypass auth)
- Optional: `E2E_TEST_USER_ID`, `KINDE_*`

Set runtime env vars on the Vercel project (Production + Preview). **Configured via CLI (2026-07-09):** `DATABASE_URL` (preview → Neon dev, production → Neon main), `E2E_TEST_BYPASS=true` (preview only). Still add manually in Vercel dashboard or CLI (do not commit values):

- `DATABASE_URL` (Production → main branch; Preview → dev branch recommended)
- `KINDE_*`, `NEXT_PUBLIC_BIM*`, `BIMAGENT_URL`, etc. (see `BIMWeb/.env.local.example`)

```bash
cd BIMWeb
# Production (main Neon branch)
printf '%s' "$MAIN_DATABASE_URL" | npx vercel env add DATABASE_URL production
# Preview (dev Neon branch)
printf '%s' "$DEV_DATABASE_URL" | npx vercel env add DATABASE_URL preview
printf 'true' | npx vercel env add E2E_TEST_BYPASS preview --yes
```

**Kinde (Production + Preview)** — copy from local `.env.local` (same app credentials; set `KINDE_SITE_URL` / redirect URLs per environment):

- `KINDE_ISSUER_URL`, `KINDE_CLIENT_ID`, `KINDE_CLIENT_SECRET`
- `KINDE_SITE_URL`, `KINDE_POST_LOGIN_REDIRECT_URL`, `KINDE_POST_LOGOUT_REDIRECT_URL`

```bash
# Example (run once per var per target; pipe value, never echo secrets)
printf '%s' "$KINDE_CLIENT_ID" | npx vercel env add KINDE_CLIENT_ID preview --yes
printf '%s' "$KINDE_CLIENT_ID" | npx vercel env add KINDE_CLIENT_ID production --yes
```

## Reconnect blockers (2026-07-08)

| Area | Status |
|------|--------|
| Neon MCP | Connected — project, branches, connection strings verified |
| Local `.env.local` / `.env.production.local` | Present; dev/main endpoints match Neon |
| GitHub secrets (both repos) | Present: `DATABASE_URL`, `VERCEL_*` |
| `pnpm db:check` (dev) | Passed — migration 0002 applied |
| Vercel link (`.vercel/project.json`) | Correct `orgId` + `projectId` |
| Vercel deploy | TypeScript fix merged; redeploy via `./deploy.sh sandbox --frontend` |
| Vercel runtime env | **Partial** — `DATABASE_URL` + preview `E2E_TEST_BYPASS`; add `KINDE_*` and service URLs before auth works in preview/prod |

## Env file patterns

| File | Committed | Purpose |
|------|-----------|---------|
| `.env.local.example` | Yes | Template for local dev |
| `.env.sandbox.example` | Yes | Sandbox/dev with `ENV=sandbox`, E2E flags |
| `.env.local` | **No** | Active local dev (Neon dev branch) |
| `.env.sandbox.local` | **No** | Optional override when `ENV=sandbox` |
| `.env.production.local` | **No** | Local prod migration checks only |

`setup-dev.sh` copies `.env.local.example` → `.env.local` when missing. Set `ENV=sandbox|production` before running scripts; `deploy.sh` exports `ENV` automatically.

## Local stack

```bash
./setup-dev.sh
./start-platform.sh              # all 5 services
docker compose up -d --build     # backends only (CI pattern)
```

Backend ports: BIMAgent `:8000`, BIMIndex `:8001`, BIMCloud `:8080`, BIMExtract `:8200`, BIMWeb `:3000`.

## Unified deploy

```bash
chmod +x deploy.sh
./deploy.sh sandbox --all --local     # preview + docker + restart
./deploy.sh production --frontend       # Vercel prod (changed BIMWeb only)
./deploy.sh production --backend      # documents GCP path, records SHA
./deploy.sh sandbox --backend --force   # rebuild docker even if unchanged
```

Change detection uses `.deploy-manifest.json` (gitignored). Template: `deploy-manifest.json`.

## CI/CD mapping

| Event | Workflow | Action |
|-------|----------|--------|
| Push `main` (meta-repo) | `.github/workflows/ecosystem-e2e.yml` | Docker backends + Playwright |
| Push `main` (meta-repo) | `.github/workflows/deploy.yml` | Path-filtered `./deploy.sh` logic |
| Push `main` (BIMWeb) | `BIMWeb/.github/workflows/cd.yml` | Vercel production deploy |
| PR (any) | Vercel Git integration | Preview deployment |
| Push `main` (bimcloud paths) | `bimrag-backend/services/bimcloud/.github/workflows/deploy.yml` | GCP Cloud Run |

**Branch → secrets:** `main` uses production secrets; PRs use preview env on Vercel and optional dev `DATABASE_URL` for E2E.

## Production backend (BIMCloud)

Production backends deploy via **bimcloud** GCP Terraform, not Vercel:

1. Configure GCP workload identity + `GCP_PROJECT_ID`, `GCP_REGION(S)`, `BIMAGENT_URL` vars
2. Push to `bimrag-backend` main with changes under `services/bimcloud/`
3. Or run `gcloud builds submit` + `terraform apply` manually (see `deploy.sh` output)

## Security

- Never commit `.env.local`, `.env.production.local`, or `.deploy-manifest.json`
- Never log `DATABASE_URL` or API keys in CI output
- `E2E_TEST_BYPASS` is for CI/sandbox only
