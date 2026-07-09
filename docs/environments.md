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
| Project | `bimrag-web` (renamed from `bimweb`) |
| Project ID | `prj_MKPAZVkmOqAbkqzVUKT23XgiFPt8` |
| Production URL (live alias) | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` |
| Production URL (pretty) | `https://bimrag-web.vercel.app` (assign custom domain when ready) |
| Preview URL pattern | `https://bimrag-web-<hash>-ashish-ps-projects-a6122913.vercel.app` (unique per deploy) |
| Project aliases | `bimrag-web-ashish-ps-projects-a6122913.vercel.app`, `bimrag-web-git-main-…`, `bimweb-dusky.vercel.app` |
| Latest READY production deploy | `dpl_B4YXNmJ4fCHfevQG72wpuArd4Xx2` (2026-07-09) — later CLI redeploys may show `BLOCKED` under Vercel Deployment Protection |

**GitHub secrets (BIMWeb repo):**

- `VERCEL_TOKEN` — personal/team token from Vercel dashboard
- `VERCEL_ORG_ID` — `team_CLXPxEDYIpsGkYyu3y2sSWFO`
- `VERCEL_PROJECT_ID` — `prj_MKPAZVkmOqAbkqzVUKT23XgiFPt8`
- `DATABASE_URL` — Neon **main** branch connection string

**GitHub secrets (Retrieval_workspace meta-repo):**

- `DATABASE_URL` — Neon dev or main (E2E uses bypass auth)
- Optional: `E2E_TEST_USER_ID`, `KINDE_*`

Set runtime env vars on the Vercel project (Production + Preview). **Verified via CLI (2026-07-09):** `DATABASE_URL` (preview + production), `E2E_TEST_BYPASS=true` (preview only), full `KINDE_*` set (including `KINDE_CLIENT_SECRET`), and `NEXT_PUBLIC_BIM*` / `NEXT_PUBLIC_APP_URL`.

- `DATABASE_URL` (Production → Neon main; Preview → Neon dev recommended)
- `KINDE_*`, `NEXT_PUBLIC_BIM*`, `BIMAGENT_URL`, etc. (see `BIMWeb/.env.local.example`)

```bash
cd BIMWeb
# Production (main Neon branch)
printf '%s' "$MAIN_DATABASE_URL" | npx vercel env add DATABASE_URL production
# Preview (dev Neon branch)
printf '%s' "$DEV_DATABASE_URL" | npx vercel env add DATABASE_URL preview
printf 'true' | npx vercel env add E2E_TEST_BYPASS preview --yes
```

**Kinde (Production + Preview)** — real `KINDE_CLIENT_SECRET` found in local gitignored env (matches Superlearn-platform; length > 20, not a placeholder) and is present on Vercel for preview + production. Local `BIMWeb/.env.local` / `.env.production.local` hold the same credentials (never commit).

Required vars:

- `KINDE_ISSUER_URL`, `KINDE_CLIENT_ID`, `KINDE_CLIENT_SECRET`
- `KINDE_SITE_URL`, `KINDE_POST_LOGIN_REDIRECT_URL`, `KINDE_POST_LOGOUT_REDIRECT_URL`

Recommended production values (alias currently serving traffic):

| Var | Production value |
|-----|------------------|
| `KINDE_SITE_URL` | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` |
| `KINDE_POST_LOGIN_REDIRECT_URL` | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app/dashboard` |
| `KINDE_POST_LOGOUT_REDIRECT_URL` | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` |
| `NEXT_PUBLIC_APP_URL` | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` |

```bash
# Example (run once per var per target; pipe value, never echo secrets)
printf '%s' "$KINDE_CLIENT_ID" | npx vercel env add KINDE_CLIENT_ID preview --yes
printf '%s' "$KINDE_CLIENT_ID" | npx vercel env add KINDE_CLIENT_ID production --yes
# Force-replace an existing var:
npx vercel env rm KINDE_CLIENT_SECRET production --yes
printf '%s' "$KINDE_CLIENT_SECRET" | npx vercel env add KINDE_CLIENT_SECRET production --yes
```

### Kinde dashboard allowlist (manual — required for live login)

In [Kinde](https://superlearnai.kinde.com) → Applications → BIMWeb / Superlearn app → **Allowed callback / logout URLs**, add:

| Type | URL |
|------|-----|
| Callback | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app/api/auth/kinde_callback` |
| Logout | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` |
| Logout (alt) | `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app/api/auth/logout` |
| Callback (pretty domain, when assigned) | `https://bimrag-web.vercel.app/api/auth/kinde_callback` |
| Local | `http://localhost:3000/api/auth/kinde_callback` |
| Local logout | `http://localhost:3000` |

If login still fails after allowlisting, confirm Vercel `KINDE_SITE_URL` / redirect vars match the allowlisted host. **Note:** `vercel env update`/`add` can hang or leave sensitive values empty; prefer Vercel REST API delete+create as `type=plain` for non-secret URLs, or set in the Vercel dashboard (Project → Settings → Environment Variables).

## Status checklist (2026-07-09)

| Area | Status |
|------|--------|
| Neon | DONE — `bimweb` project; `main` + `dev` ready; migration `0002` applied |
| Vercel project | DONE — `bimrag-web`; production alias returns 200 (BIMWeb landing) |
| Vercel env names | DONE — `DATABASE_URL`, `KINDE_*` (incl. secret), `NEXT_PUBLIC_*` on preview + production |
| Kinde secret (local) | DONE — real secret in gitignored `.env.local` (matches Superlearn-platform) |
| Kinde dashboard allowlist | **NEEDS USER** — add production callback/logout URLs (table above) |
| Kinde redirect URL values on Vercel | **DONE** — production + preview set to `https://bimrag-web-ashish-ps-projects-a6122913.vercel.app` (post-login `/dashboard`); verified via Vercel API (recreated as plain after sensitive CLI/API updates left empty values) |
| Custom domain | **NEEDS USER** — assign `bimrag-web.vercel.app` or own domain in Vercel |
| GitHub secrets | **NEEDS USER** — `gh auth status` invalid keyring token; run `gh auth refresh -h github.com`, then verify secret names on `Retrieval_workspace` |
| Backend GCP / Cloud Run | **NEEDS USER** — `./deploy.sh production --backend` documents path; needs GCP WI + vars |
| Local stack | **BLOCKED** — Docker Desktop not installed (`/Applications/Docker.app` missing; no `docker` on PATH / `~/.docker/bin`); all local services offline |
| Deployment Protection | Note — unauthenticated `curl` may 302 to Vercel SSO; app itself is healthy (MCP fetch 200) |

## Reconnect blockers (2026-07-08 → updated 2026-07-09)

| Area | Status |
|------|--------|
| Neon MCP | Connected — project, branches, connection strings verified |
| Local `.env.local` / `.env.production.local` | Present; real Kinde secret; production.local URLs set to live alias |
| GitHub secrets (both repos) | Previously set (`DATABASE_URL`, `VERCEL_*`); re-verify after `gh auth refresh` |
| `pnpm db:check` (dev) | Passed — migration 0002 applied |
| Vercel link (`.vercel/project.json`) | Correct `orgId` + `projectId` |
| Vercel deploy | READY production deploy serving alias; build gate in `deploy.sh` |
| Vercel runtime env | `DATABASE_URL`, `KINDE_*` (real secret present), `NEXT_PUBLIC_*`, preview `E2E_TEST_BYPASS` |

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
./start-platform.sh --status     # health table
docker compose up -d --build     # backends only (CI pattern)
./deploy.sh sandbox --backend --local   # compose build + optional platform restart
```

**Blocker (2026-07-09):** Docker Desktop is not installed on this host (`/Applications/Docker.app` absent; no CLI under `/usr/local/bin`, `/opt/homebrew/bin`, or `~/.docker/bin`). Install Docker Desktop, then `./deploy.sh sandbox --backend --local` or `./start-platform.sh`. Frontend-only: `cd BIMWeb && pnpm dev`.

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

`./deploy.sh production --backend` does **not** push to Cloud Run itself — it records the backend SHA and prints the GCP path. Actual rollout:

1. Configure GitHub secrets/vars on `ashishpatill/bimrag-backend`:
   - Secrets: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`
   - Vars: `GCP_PROJECT_ID`, `GCP_REGION` (or `GCP_REGIONS`), `BIMAGENT_URL`
2. Push to `bimrag-backend` `main` with changes under `services/bimcloud/` (triggers `.github/workflows/deploy.yml`)
3. Or run manually (authenticated `gcloud`):

```bash
cd bimrag-backend/services/bimcloud
gcloud builds submit --tag "gcr.io/$GCP_PROJECT_ID/bimcloud:$(git rev-parse --short HEAD)"
cd deploy/terraform && terraform init && terraform apply
```

Sandbox backends: `./deploy.sh sandbox --backend --local` → `docker compose up -d --build` (requires Docker).

## Security

- Never commit `.env.local`, `.env.production.local`, or `.deploy-manifest.json`
- Never log `DATABASE_URL` or API keys in CI output
- `E2E_TEST_BYPASS` is for CI/sandbox only
