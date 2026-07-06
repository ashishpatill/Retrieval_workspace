#!/usr/bin/env bash
# =============================================================================
#  BIMRAG Ecosystem — Developer environment bootstrap
# =============================================================================
#  Run from meta-repo root after:
#    git clone --recurse-submodules <url>
#  or:
#    git submodule update --init --recursive
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$ROOT/bimrag-backend"
BIMWEB="$ROOT/BIMWeb"
SERVICES=(bimagent bimcloud bimextract bimindex)

log() { echo "[setup-dev] $*"; }
die() { echo "[setup-dev] ERROR: $*" >&2; exit 1; }

if [[ ! -d "$BACKEND/services" ]]; then
  die "bimrag-backend submodule missing. Run: git submodule update --init --recursive"
fi
if [[ ! -f "$BIMWEB/package.json" ]]; then
  die "BIMWeb submodule missing. Run: git submodule update --init --recursive"
fi

install_python_service() {
  local svc="$1"
  local dir="$BACKEND/services/$svc"
  [[ -d "$dir" ]] || die "service directory not found: $dir"

  log "Python venv + deps: $svc"
  cd "$dir"

  if [[ ! -d .venv ]]; then
    python3 -m venv .venv
  fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  python -m pip install -U pip wheel

  if [[ -f pyproject.toml ]] && grep -q '^\[project\]' pyproject.toml; then
    pip install -e ".[dev]"
  elif [[ -f requirements.txt ]]; then
    pip install -r requirements.txt
  else
    deactivate
    die "no requirements.txt or [project] in pyproject.toml for $svc"
  fi
  deactivate
}

for svc in "${SERVICES[@]}"; do
  install_python_service "$svc"
done

log "Node deps: BIMWeb"
cd "$BIMWEB"
if ! command -v pnpm >/dev/null 2>&1; then
  die "pnpm is required. Install via: corepack enable && corepack prepare pnpm@9 --activate"
fi
pnpm install

if [[ -f "$BIMWEB/.env.local.example" && ! -f "$BIMWEB/.env.local" ]]; then
  cp "$BIMWEB/.env.local.example" "$BIMWEB/.env.local"
  log "Created BIMWeb/.env.local from .env.local.example"
elif [[ ! -f "$BIMWEB/.env.local.example" ]]; then
  log "BIMWeb/.env.local.example not present — skip env copy (see BIMWeb/README.md)"
fi

cat <<EOF

Setup complete.

Next steps:
  1. Review BIMWeb/.env.local (Kinde, database, API URLs) if you use auth locally.
  2. From this directory, start the stack:
       ./start-platform.sh
  3. Optional Docker backends only:
       docker compose up -d --build

Docs: README.md, API_CONTRACT.md
EOF
