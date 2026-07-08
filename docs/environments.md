# BIMRAG Environments

This meta-repo deploys **BIMWeb** (Vercel + Neon) and **bimrag-backend** services (Docker locally; GCP for production BIMCloud when configured).

## Environment matrix

| | **Sandbox** | **Production** |
|---|---|---|
| **Purpose** | Preview, dev, CI E2E | Live users |
| **Frontend** | Vercel preview (`vercel`) | Vercel production (`vercel --prod`) |
| **Database** | Neon branch `dev` | Neon branch `main` |
| **Backends** | `docker compose` on changed services | GCP Cloud Run via BIMCloud Terraform (if configured), else docker compose |
| **Local dev** | `./start-platform.sh` + Neon `dev` in `BIMWeb/.env.local` | Not used for day-to-day dev |

## Neon (Postgres)

| Branch | Neon ID | Use |
|---|---|---|
| `main` | `br-gentle-cloud-atsvon99` | Production `DATABASE_URL` |
| `dev` | `br-rapid-union-atj3wffr` | Sandbox / local `DATABASE_URL` |

Project: **bimweb** (`blue-cake-13205477`, `aws-us-east-1`).

- Local: copy `BIMWeb/.env.sandbox.example` → `BIMWeb/.env.local` and set `DATABASE_URL` from the Neon console or `get_connection_string` (dev branch).
- CI: GitHub secret `DATABASE_URL` on `Retrieval_workspace` (ecosystem E2E) and `BIMWeb` (CD/migrations). Use **dev** for CI, **main** for production Vercel env.
- Migrations: `cd BIMWeb && pnpm db:migrate` (requires `DATABASE_URL` in `.env.local`).

## Vercel (BIMWeb)

| Setting | Source |
|---|---|
| `VERCEL_ORG_ID` | Team id from Vercel → Settings (e.g. `team_…`) |
| `VERCEL_PROJECT_ID` | Project → Settings → General |
| `VERCEL_TOKEN` | Vercel account token (CI only) |

Link the project once from `BIMWeb/`:

```bash
cd BIMWeb
npx vercel link
```

Runtime env vars (set in Vercel dashboard, not committed):

- `DATABASE_URL` — Neon **main** for production, **dev** for preview
- `KINDE_*` — OAuth (issuer, client id/secret, redirect URLs)
- `NEXT_PUBLIC_BIMAGENT_URL`, `NEXT_PUBLIC_BIMINDEX_URL`, `NEXT_PUBLIC_BIMEXTRACT_URL`, `NEXT_PUBLIC_BIMCLOUD_URL`
- Optional: `SENTRY_DSN`, `NEXT_PUBLIC_POSTHOG_KEY`, Upstash, S3

## Backend services

| Service | Port | Sandbox deploy | Production deploy |
|---|---|---|---|
| BIMIndex | 8001 | docker compose | docker compose (or host of your choice) |
| BIMExtract | 8200 | docker compose | docker compose |
| BIMAgent | 8000 | docker compose | docker compose |
| BIMCloud | 8080 | docker compose | `gcloud` + Terraform (`bimrag-backend/services/bimcloud/deploy/terraform`) when `GCP_PROJECT_ID` and WIF secrets are set |

## Deploy commands

```bash
# Sandbox — full stack
./deploy.sh sandbox --all

# Production — frontend only
./deploy.sh production --frontend

# Changed backend services only (compose)
./deploy.sh sandbox --backend

# Refresh submodules + restart local platform
./deploy.sh sandbox --local
```

Change detection: `./deploy.sh` compares git/tree fingerprints in `.deploy-manifest.json` (gitignored). Template: `.deploy-manifest.template.json`.

## GitHub Actions secrets

### `Retrieval_workspace` (meta-repo)

| Secret | Value |
|---|---|
| `DATABASE_URL` | Neon **dev** connection string (ecosystem E2E) |

### `BIMWeb` (submodule repo)

| Secret | Value |
|---|---|
| `DATABASE_URL` | Neon **main** (prod CD) or **dev** (preview) |
| `VERCEL_TOKEN` | Vercel API token |
| `VERCEL_ORG_ID` | `team_CLXPxEDYIpsGkYyu3y2sSWFO` (Ashish P's projects) |
| `VERCEL_PROJECT_ID` | `prj_MKPAZVkmOqAbkqzVUKT23XgiFPt8` (linked via `vercel link --project bimweb`) |
| `KINDE_*` | Auth for E2E / CD |

Workflows:

- `.github/workflows/deploy.yml` — meta-repo orchestration (path filters)
- `BIMWeb/.github/workflows/cd.yml` — Vercel production on `main`
- `.github/workflows/ecosystem-e2e.yml` — Playwright + docker compose backends

## Security

- Never commit `.env.local`, `.deploy-manifest.json`, or Neon connection strings.
- Use Neon **dev** for local and CI; reserve **main** for production Vercel only.
- Rotate credentials if a connection string was exposed in logs or chat.
