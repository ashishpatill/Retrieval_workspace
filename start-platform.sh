#!/usr/bin/env bash
# =============================================================================
#  BIMRAG Ecosystem — One-Command Dev Platform
# =============================================================================
#  Starts all 5 services, health-checks each, streams logs, and prints a
#  status table. Ctrl+C gracefully shuts everything down.
#
#  Services:
#    BIMAgent   :8000  (orchestrator, system python)   uvicorn app.main:app
#    BIMIndex   :8001  (tri-modal retrieval, .venv)     uvicorn server:app
#    BIMCloud   :8080  (edge gateway, system python)    uvicorn src.gateway.router:app
#    BIMExtract :8200  (ingestion + 4 modules, sys py)  uvicorn server:app
#    BIMWeb     :3000  (Next.js UI, pnpm)               pnpm dev
#
#  Usage:
#    ./start-platform.sh              start everything
#    ./start-platform.sh --demo       start + seed sample data + run scenarios
#    ./start-platform.sh --stop       stop a running platform
#    ./start-platform.sh --status     show status of running services
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT/logs"
PID_FILE="$LOG_DIR/platform.pids"
mkdir -p "$LOG_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
log()   { echo -e "${GREEN}[platform]${NC} $1"; }
warn()  { echo -e "${YELLOW}[platform]${NC} $1"; }
err()   { echo -e "${RED}[platform]${NC} $1" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}"; }

# ── Service definitions ──────────────────────────────────────────────────────
# name | port | health_path | dir | command...
declare -a SERVICES=(
  "BIMIndex|8001|/health|bimrag-backend/services/bimindex|.venv/bin/python -m uvicorn server:app --host 127.0.0.1 --port 8001"
  "BIMExtract|8200|/health|bimrag-backend/services/bimextract|.venv/bin/python -m uvicorn server:app --host 127.0.0.1 --port 8200"
  "BIMAgent|8000|/health|bimrag-backend/services/bimagent|.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000"
  "BIMCloud|8080|/health|bimrag-backend/services/bimcloud|.venv/bin/python -m uvicorn src.gateway.router:app --host 127.0.0.1 --port 8080"
  "BIMWeb|3000||BIMWeb|pnpm dev"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
port_open() { curl -fsS "http://127.0.0.1:$1$2" >/dev/null 2>&1; }

wait_health() {
  local name="$1" port="$2" path="$3" max="${4:-40}"
  printf "  ${DIM}Waiting for %s on :%s ...${NC}" "$name" "$port"
  for _ in $(seq 1 "$max"); do
    if port_open "$port" "$path"; then
      printf " ${GREEN}ready${NC}\n"
      return 0
    fi
    printf "${DIM}.${NC}"
    sleep 1
  done
  printf " ${RED}timeout${NC}\n"
  return 1
}

is_running() { kill -0 "$1" 2>/dev/null; }

# ── Stop ─────────────────────────────────────────────────────────────────────
stop_platform() {
  header "Stopping platform"
  if [[ -f "$PID_FILE" ]]; then
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      if is_running "$pid"; then
        kill "$pid" 2>/dev/null && log "Stopped PID $pid"
      fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  # Sweep: kill any uvicorn/pnpm bound to our ports
  for port in 8000 8001 8080 8200 3000; do
    local pids
    pids=$(lsof -ti tcp:"$port" 2>/dev/null || true)
    [[ -n "$pids" ]] && kill $pids 2>/dev/null && log "Freed port :$port" || true
  done
  log "Platform stopped."
}

# ── Status ───────────────────────────────────────────────────────────────────
show_status() {
  header "Platform status"
  printf "  %-12s %-7s %-10s %s\n" "SERVICE" "PORT" "STATUS" "URL"
  for svc in "${SERVICES[@]}"; do
    IFS='|' read -r name port path dir cmd <<< "$svc"
    local url="http://127.0.0.1:$port"
    local status
    if [[ -n "$path" ]] && port_open "$port" "$path"; then
      status="${GREEN}● online${NC}"
    elif [[ -z "$path" ]] && curl -fsS "$url" >/dev/null 2>&1; then
      status="${GREEN}● online${NC}"
    else
      status="${RED}○ offline${NC}"
    fi
    printf "  %-12s %-7s %-22b %s\n" "$name" "$port" "$status" "$url"
  done
}

# ── Start ────────────────────────────────────────────────────────────────────
start_platform() {
  header "Starting BIMRAG Ecosystem (5 services)"
  : > "$PID_FILE"

  # Backends first (in registration order), then BIMWeb.
  for svc in "${SERVICES[@]}"; do
    IFS='|' read -r name port path dir cmd <<< "$svc"
    log "Starting $name → :$port"
    (
      cd "$ROOT/$dir"
      # BIMAgent needs cross-repo URLs; BIMIndex needs its venv on PATH
      case "$name" in
        BIMAgent) export BIMINDEX_URL="http://localhost:8001" BIMEXTRACT_URL="http://localhost:8200" ;;
        BIMIndex)
          export DENSE_EMBEDDING_BACKEND="${DENSE_EMBEDDING_BACKEND:-colqwen2.5}"
          export COLQWEN_MODEL="${COLQWEN_MODEL:-vidore/colqwen2.5-v0.2}"
          export COLQWEN_DEVICE="${COLQWEN_DEVICE:-auto}"
          export COLQWEN_COMPRESSION="${COLQWEN_COMPRESSION:-int8}"
          export BIMINDEX_DENSE_DIMENSIONS="${BIMINDEX_DENSE_DIMENSIONS:-128}"
          ;;
      esac
      exec env PYTHONPATH="." $cmd
    ) >"$LOG_DIR/$name.log" 2>&1 &
    local pid=$!
    echo "$pid" >> "$PID_FILE"
    log "  $name started (PID $pid, log: logs/$name.log)"
  done

  # Health-check the backends (skip BIMWeb which has no /health).
  header "Health checks"
  for svc in "${SERVICES[@]}"; do
    IFS='|' read -r name port path dir cmd <<< "$svc"
    [[ -z "$path" ]] && continue
    wait_health "$name" "$port" "$path" || warn "$name did not become healthy in time — check logs/$name.log"
  done
  # BIMWeb: just wait for the port to answer.
  wait_health "BIMWeb" "3000" "/" 60 || warn "BIMWeb not responding — check logs/BIMWeb.log"

  echo
  show_status
  header "Ready"
  echo -e "  ${BOLD}BIMWeb UI:${NC}        ${CYAN}http://localhost:3000${NC}"
  echo -e "  ${BOLD}Search UI:${NC}        ${CYAN}http://localhost:3000/dashboard/search${NC}"
  echo -e "  ${BOLD}Deployments UI:${NC}   ${CYAN}http://localhost:3000/dashboard/deployments${NC}"
  echo -e "  ${BOLD}API docs:${NC}"
  echo -e "    BIMAgent:   ${CYAN}http://localhost:8000/docs${NC}"
  echo -e "    BIMIndex:   ${CYAN}http://localhost:8001/docs${NC}"
  echo -e "    BIMExtract: ${CYAN}http://localhost:8200/docs${NC}"
  echo -e "    BIMCloud:   ${CYAN}http://localhost:8080/docs${NC}"
  echo -e "  ${DIM}Logs: tail -f logs/*.log   |   Stop: Ctrl+C or ./start-platform.sh --stop${NC}"
  echo
}

# ── Cleanup trap ─────────────────────────────────────────────────────────────
cleanup() {
  echo
  stop_platform
}
trap cleanup EXIT INT TERM

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  --stop)   trap - EXIT INT TERM; stop_platform; exit 0 ;;
  --status) trap - EXIT INT TERM; show_status; exit 0 ;;
  --demo)   start_platform; "$ROOT/run-scenarios.sh" --seed; "$ROOT/run-scenarios.sh"
            echo -e "\n${GREEN}Demo complete — platform staying alive for interactive use.${NC}"
            echo -e "${DIM}Open http://localhost:3000/dashboard/search — press Ctrl+C to stop.${NC}"
            wait ;;
  ""|start) start_platform; echo -e "${DIM}Press Ctrl+C to stop.${NC}"; wait ;;
  *) err "Unknown option: $1"; echo "Usage: $0 [--demo|--stop|--status]"; exit 1 ;;
esac
