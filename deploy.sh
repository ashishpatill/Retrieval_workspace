#!/usr/bin/env bash
# =============================================================================
#  BIMRAG Ecosystem — Unified Deploy
# =============================================================================
#  Usage:
#    ./deploy.sh [production|sandbox] [--frontend|--backend|--all] [--local]
#
#  Environments:
#    production  — Vercel --prod, Neon main branch, GCP BIMCloud (if configured)
#    sandbox     — Vercel preview, Neon dev branch, docker compose backends
#
#  Targets:
#    --frontend  — BIMWeb only (Vercel)
#    --backend   — bimrag-backend services only
#    --all       — frontend + backend (default)
#    --local     — submodule sync + restart local platform (no cloud deploy)
#
#  Change detection uses .deploy-manifest.json (gitignored runtime state).
#  Seed from .deploy-manifest.template.json on first run.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$ROOT/.deploy-manifest.json"
MANIFEST_TEMPLATE="$ROOT/.deploy-manifest.template.json"
COMPOSE_FILE="$ROOT/docker-compose.yml"
BIMWEB_DIR="$ROOT/BIMWeb"
SERVICES_DIR="$ROOT/bimrag-backend/services"
BIMCLOUD_DEPLOY_DIR="$SERVICES_DIR/bimcloud/deploy/terraform"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[deploy]${NC} $1"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $1"; }
err()  { echo -e "${RED}[deploy]${NC} $1" >&2; }
die()  { err "$1"; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./deploy.sh [production|sandbox] [--frontend|--backend|--all] [--local]

Examples:
  ./deploy.sh sandbox --all
  ./deploy.sh production --frontend
  ./deploy.sh sandbox --backend
  ./deploy.sh sandbox --local
EOF
}

ENVIRONMENT="${1:-sandbox}"
shift || true

TARGET="all"
LOCAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --frontend) TARGET="frontend" ;;
    --backend)  TARGET="backend" ;;
    --all)      TARGET="all" ;;
    --local)    LOCAL=true ;;
    -h|--help)  usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

case "$ENVIRONMENT" in
  production|sandbox) ;;
  *) die "Environment must be 'production' or 'sandbox' (got: $ENVIRONMENT)" ;;
esac

# ── Manifest helpers ───────────────────────────────────────────────────────────
ensure_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    if [[ -f "$MANIFEST_TEMPLATE" ]]; then
      cp "$MANIFEST_TEMPLATE" "$MANIFEST"
      log "Initialized $MANIFEST from template"
    else
      echo '{"version":1,"last_deploy":{},"fingerprints":{}}' > "$MANIFEST"
      log "Created empty $MANIFEST"
    fi
  fi
}

fingerprint_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "missing"
    return
  fi
  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local rel="${path#"$ROOT"/}"
    if git -C "$ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      git -C "$ROOT" rev-parse "HEAD:$rel" 2>/dev/null || echo "untracked"
      return
    fi
  fi
  find "$path" -type f ! -path '*/node_modules/*' ! -path '*/.venv/*' ! -path '*/__pycache__/*' \
    -exec shasum -a 256 {} + 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

manifest_get() {
  local key="$1"
  python3 - "$MANIFEST" "$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
print(data.get("fingerprints", {}).get(key, ""))
PY
}

manifest_set() {
  local key="$1" value="$2"
  python3 - "$MANIFEST" "$key" "$value" "$ENVIRONMENT" <<'PY'
import json, sys, datetime
path, key, value, env = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
data.setdefault("fingerprints", {})[key] = value
data.setdefault("last_deploy", {})[key] = {
    "environment": env,
    "at": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

changed_since_last() {
  local key="$1" path="$2"
  local current stored
  current="$(fingerprint_path "$path")"
  stored="$(manifest_get "$key")"
  [[ "$current" != "$stored" ]]
}

mark_deployed() {
  local key="$1" path="$2"
  manifest_set "$key" "$(fingerprint_path "$path")"
}

# ── Local platform ─────────────────────────────────────────────────────────────
deploy_local() {
  log "Syncing submodules"
  git -C "$ROOT" submodule update --init --recursive

  if [[ -x "$ROOT/start-platform.sh" ]]; then
    log "Restarting local platform"
    "$ROOT/start-platform.sh" --stop || true
    "$ROOT/start-platform.sh" &
    log "Local platform starting in background (logs: logs/*.log)"
  else
    die "start-platform.sh not found"
  fi
}

# ── Frontend (Vercel) ────────────────────────────────────────────────────────
deploy_frontend() {
  [[ -d "$BIMWEB_DIR" ]] || die "BIMWeb directory not found"

  local vercel_cmd
  if command -v vercel >/dev/null 2>&1; then
    vercel_cmd="vercel"
  elif command -v npx >/dev/null 2>&1; then
    vercel_cmd="npx vercel@latest"
  else
    die "Vercel CLI not found (install: npm i -g vercel)"
  fi

  log "Deploying BIMWeb to Vercel ($ENVIRONMENT)"
  (
    cd "$BIMWEB_DIR"
    if [[ "$ENVIRONMENT" == "production" ]]; then
      $vercel_cmd --prod --yes
    else
      $vercel_cmd --yes
    fi
  )
  mark_deployed "frontend:BIMWeb" "$BIMWEB_DIR"
}

# ── Backend helpers ────────────────────────────────────────────────────────────
backend_service_paths() {
  local names=("bimindex" "bimextract" "bimagent" "bimcloud")
  local name
  for name in "${names[@]}"; do
    echo "$name|$SERVICES_DIR/$name|$name"
  done
}

compose_up_services() {
  local -a services=("$@")
  command -v docker >/dev/null 2>&1 || die "docker not found (required for sandbox backend deploy)"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    die "docker-compose.yml not found at $COMPOSE_FILE"
  fi

  if [[ ${#services[@]} -eq 0 ]]; then
    log "No backend service changes detected — skipping docker compose"
    return 0
  fi

  log "Building and starting changed services: ${services[*]}"
  docker compose -f "$COMPOSE_FILE" build "${services[@]}"
  docker compose -f "$COMPOSE_FILE" up -d "${services[@]}"

  local svc port
  for svc in "${services[@]}"; do
    case "$svc" in
      bimindex)   port=8001 ;;
      bimextract) port=8200 ;;
      bimagent)   port=8000 ;;
      bimcloud)   port=8080 ;;
      *) continue ;;
    esac
    log "Waiting for $svc health on :$port"
    for _ in $(seq 1 60); do
      if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
        log "$svc is healthy"
        break
      fi
      sleep 2
    done
  done
}

deploy_backend_gcp() {
  command -v gcloud >/dev/null 2>&1 || return 1
  [[ -d "$BIMCLOUD_DEPLOY_DIR" ]] || return 1
  [[ -f "$SERVICES_DIR/bimcloud/Dockerfile" ]] || return 1

  local project_id="${GCP_PROJECT_ID:-}"
  if [[ -z "$project_id" ]]; then
    project_id="$(gcloud config get-value project 2>/dev/null || true)"
  fi
  [[ -n "$project_id" && "$project_id" != "(unset)" ]] || return 1

  log "Deploying BIMCloud to GCP ($project_id)"
  local image="gcr.io/${project_id}/bimcloud:latest"
  gcloud builds submit "$SERVICES_DIR/bimcloud" --tag "$image"

  (
    cd "$BIMCLOUD_DEPLOY_DIR"
    terraform init -input=false
    terraform apply -auto-approve -input=false
  )
  return 0
}

deploy_backend_compose() {
  local -a changed=()
  local entry name path key
  while IFS='|' read -r name path key; do
    [[ -d "$path" ]] || continue
    if changed_since_last "backend:$key" "$path"; then
      changed+=("$key")
    fi
  done < <(backend_service_paths)

  if changed_since_last "backend:docker-compose" "$COMPOSE_FILE"; then
    changed+=("bimindex" "bimextract" "bimagent" "bimcloud")
  fi

  # Deduplicate service list
  if [[ ${#changed[@]} -gt 0 ]]; then
    local -a unique=()
    local s u seen
    for s in "${changed[@]}"; do
      seen=false
      for u in "${unique[@]:-}"; do
        [[ "$u" == "$s" ]] && seen=true && break
      done
      $seen || unique+=("$s")
    done
    changed=("${unique[@]}")
  fi

  compose_up_services "${changed[@]}"

  local entry2 name2 path2 key2
  while IFS='|' read -r name2 path2 key2; do
    [[ -d "$path2" ]] || continue
    mark_deployed "backend:$key2" "$path2"
  done < <(backend_service_paths)
  mark_deployed "backend:docker-compose" "$COMPOSE_FILE"
}

deploy_backend() {
  if [[ "$ENVIRONMENT" == "production" ]]; then
    if deploy_backend_gcp; then
      mark_deployed "backend:bimcloud" "$SERVICES_DIR/bimcloud"
      log "GCP production backend deploy complete"
      return 0
    fi
    warn "GCP BIMCloud deploy unavailable — falling back to docker compose"
  fi

  deploy_backend_compose
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  ensure_manifest

  log "Environment: ${BOLD}$ENVIRONMENT${NC} | Target: ${BOLD}$TARGET${NC} | Local: $LOCAL"

  if $LOCAL; then
    deploy_local
    return 0
  fi

  case "$TARGET" in
    frontend)
      deploy_frontend
      ;;
    backend)
      deploy_backend
      ;;
    all)
      deploy_frontend
      deploy_backend
      ;;
  esac

  log "Deploy complete"
}

main
