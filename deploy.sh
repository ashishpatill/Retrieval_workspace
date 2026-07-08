#!/usr/bin/env bash
# =============================================================================
#  BIMRAG Ecosystem — Unified deploy automation
# =============================================================================
#  Usage:
#    ./deploy.sh [production|sandbox] [--frontend|--backend|--all] [--local] [--force]
#
#  Examples:
#    ./deploy.sh production --all          # deploy changed frontend + backend
#    ./deploy.sh sandbox --frontend        # Vercel preview for BIMWeb
#    ./deploy.sh sandbox --backend --local # docker compose + restart local stack
#    ./deploy.sh production --all --force  # ignore change detection
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$ROOT/.deploy-manifest.json"
MANIFEST_TEMPLATE="$ROOT/deploy-manifest.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()   { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[deploy]${NC} $*"; }
err()   { echo -e "${RED}[deploy]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }
header(){ echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}"; }

ENV_TARGET="${1:-sandbox}"
shift || true

DEPLOY_FRONTEND=0
DEPLOY_BACKEND=0
RESTART_LOCAL=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --frontend) DEPLOY_FRONTEND=1 ;;
    --backend)  DEPLOY_BACKEND=1 ;;
    --all)      DEPLOY_FRONTEND=1; DEPLOY_BACKEND=1 ;;
    --local)    RESTART_LOCAL=1 ;;
    --force)    FORCE=1 ;;
    -h|--help)
      sed -n '4,12p' "$0"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

[[ "$DEPLOY_FRONTEND" -eq 1 || "$DEPLOY_BACKEND" -eq 1 ]] || DEPLOY_FRONTEND=1

case "$ENV_TARGET" in
  production|prod) ENV_TARGET="production" ;;
  sandbox|dev|preview) ENV_TARGET="sandbox" ;;
  *) die "Environment must be production or sandbox (got: $ENV_TARGET)" ;;
esac

export ENV="$ENV_TARGET"

ensure_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    cp "$MANIFEST_TEMPLATE" "$MANIFEST"
    log "Initialized $MANIFEST from template"
  fi
}

component_sha() {
  local path="$1"
  git -C "$ROOT/$path" rev-parse HEAD 2>/dev/null || echo "unknown"
}

manifest_last_sha() {
  local component="$1"
  python3 - "$MANIFEST" "$component" <<'PY'
import json, sys
path, component = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
print(data.get("components", {}).get(component, {}).get("last_sha") or "")
PY
}

update_manifest() {
  local component="$1" sha="$2"
  python3 - "$MANIFEST" "$component" "$sha" "$ENV_TARGET" <<'PY'
import json, sys
from datetime import datetime, timezone
path, component, sha, env = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
data.setdefault("components", {}).setdefault(component, {})
data["components"][component]["last_sha"] = sha
data["components"][component]["last_deployed_at"] = datetime.now(timezone.utc).isoformat()
data["components"][component]["environment"] = env
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

needs_deploy() {
  local component="$1" path="$2"
  local current last
  current="$(component_sha "$path")"
  last="$(manifest_last_sha "$component")"
  if [[ "$FORCE" -eq 1 ]]; then
    echo "$current"
    return 0
  fi
  if [[ -z "$last" || "$current" != "$last" ]]; then
    echo "$current"
    return 0
  fi
  return 1
}

load_bimweb_env() {
  local env_file="$ROOT/BIMWeb/.env.local"
  if [[ "$ENV_TARGET" == "production" && -f "$ROOT/BIMWeb/.env.production.local" ]]; then
    env_file="$ROOT/BIMWeb/.env.production.local"
  elif [[ -f "$ROOT/BIMWeb/.env.sandbox.local" ]]; then
    env_file="$ROOT/BIMWeb/.env.sandbox.local"
  fi
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

deploy_frontend() {
  header "Frontend (BIMWeb → Vercel)"
  local sha
  sha="$(needs_deploy frontend BIMWeb)" || {
    log "Frontend unchanged since last deploy — skipping (use --force)"
    return 0
  }

  cd "$ROOT/BIMWeb"
  if ! command -v npx >/dev/null 2>&1; then
    die "npx is required for Vercel deploy"
  fi

  if [[ -f .vercel/project.json ]]; then
    export VERCEL_ORG_ID="${VERCEL_ORG_ID:-$(python3 -c "import json; print(json.load(open('.vercel/project.json'))['orgId'])")}"
    export VERCEL_PROJECT_ID="${VERCEL_PROJECT_ID:-$(python3 -c "import json; print(json.load(open('.vercel/project.json'))['projectId'])")}"
  fi

  local vercel_args=("--yes")
  if [[ "$ENV_TARGET" == "production" ]]; then
    vercel_args+=("--prod")
  fi

  if [[ ! -f .vercel/project.json ]]; then
    warn "BIMWeb/.vercel/project.json missing — run: cd BIMWeb && npx vercel link"
    warn "Attempting deploy anyway (requires VERCEL_TOKEN or interactive login)"
  fi

  log "Deploying BIMWeb ($ENV_TARGET) @ ${sha:0:8}"
  if ! npx vercel@latest deploy "${vercel_args[@]}"; then
    err "Vercel deploy failed (exit $?)"
    return 1
  fi
  update_manifest frontend "$sha"
  log "Frontend deploy complete"
}

deploy_backend_local() {
  header "Backend (docker compose — sandbox/local)"
  local sha
  sha="$(needs_deploy backend bimrag-backend)" || {
    log "Backend unchanged since last deploy — skipping (use --force)"
    return 0
  }

  cd "$ROOT"
  log "Building and starting backend services @ ${sha:0:8}"
  if ! docker compose up -d --build; then
    err "docker compose up failed (exit $?)"
    return 1
  fi
  update_manifest backend "$sha"
  log "Backend docker compose stack is up"
}

deploy_backend_production() {
  header "Backend (production — BIMCloud GCP)"
  local sha
  sha="$(needs_deploy backend bimrag-backend)" || {
    log "Backend unchanged since last deploy — skipping (use --force)"
    return 0
  }

  local cloud_dir="$ROOT/bimrag-backend/services/bimcloud"
  [[ -d "$cloud_dir/deploy/terraform" ]] || die "Missing BIMCloud terraform at $cloud_dir/deploy/terraform"

  warn "Production backend deploy uses BIMCloud GCP pipeline."
  echo -e "  ${DIM}Path:${NC} bimrag-backend/services/bimcloud/.github/workflows/deploy.yml"
  echo -e "  ${DIM}Trigger:${NC} push to bimrag-backend main (bimcloud paths) or manual workflow_dispatch"
  echo -e "  ${DIM}Requires:${NC} GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT, GCP_PROJECT_ID vars"
  echo
  echo -e "  ${DIM}Manual (authenticated gcloud):${NC}"
  echo "    cd bimrag-backend/services/bimcloud"
  echo "    gcloud builds submit --tag gcr.io/\$GCP_PROJECT_ID/bimcloud:${sha:0:8}"
  echo "    cd deploy/terraform && terraform init && terraform apply"

  if [[ -n "${CI:-}" ]]; then
    die "Production backend deploy must run via bimcloud GitHub workflow or authenticated gcloud"
  fi

  update_manifest backend "$sha"
  log "Recorded backend SHA; run bimcloud deploy workflow for Cloud Run rollout"
}

restart_local_stack() {
  header "Local stack refresh"
  cd "$ROOT"
  git submodule update --init --recursive
  if [[ -x "$ROOT/start-platform.sh" ]]; then
    "$ROOT/start-platform.sh" --stop || true
    "$ROOT/start-platform.sh" &
    disown || true
    log "Local platform restarted in background (logs: logs/*.log)"
  else
    warn "start-platform.sh not executable — skipped"
  fi
}

main() {
  header "BIMRAG deploy ($ENV_TARGET)"
  ensure_manifest
  load_bimweb_env

  local exit_code=0
  if [[ "$DEPLOY_FRONTEND" -eq 1 ]]; then
    deploy_frontend || exit_code=$?
  fi
  if [[ "$DEPLOY_BACKEND" -eq 1 ]]; then
    if [[ "$ENV_TARGET" == "production" ]]; then
      deploy_backend_production || exit_code=$?
    else
      deploy_backend_local || exit_code=$?
    fi
  fi
  if [[ "$RESTART_LOCAL" -eq 1 ]]; then
    restart_local_stack || exit_code=$?
  fi

  header "Done"
  if [[ "$exit_code" -ne 0 ]]; then
    err "Deploy finished with errors (exit $exit_code)"
  else
    log "Deploy finished successfully"
  fi
  exit "$exit_code"
}

main
