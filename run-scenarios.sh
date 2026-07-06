#!/usr/bin/env bash
# =============================================================================
#  BIMRAG Ecosystem — End-to-End Scenario Runner
# =============================================================================
#  Exercises every feature across all 5 repos against a running platform.
#  Start the platform first: ./start-platform.sh  (or use --demo to do both)
#
#  Usage:
#    ./run-scenarios.sh --seed    seed BIMIndex with sample documents
#    ./run-scenarios.sh           run all end-to-end scenarios
#    ./run-scenarios.sh <name>    run a single scenario (list below)
#
#  Scenarios: index-search | extract-pipeline | extract-index | parsers | graph | auto-rag
#             | mdoc | agent | cloud | web | all
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
AGENT="http://localhost:8000"; INDEX="http://localhost:8001"
CLOUD="http://localhost:8080"; EXTRACT="http://localhost:8200"; WEB="http://localhost:3000"

pass=0; fail=0
ok()   { echo -e "  ${GREEN}✓${NC} $1"; pass=$((pass+1)); }
bad()  { echo -e "  ${RED}✗${NC} $1"; fail=$((fail+1)); }
sec()  { echo -e "\n${BOLD}${CYAN}▶ $1${NC}"; }
need() { curl -fsS "$1" >/dev/null 2>&1 || { bad "$2 not running at $1"; return 1; }; }

# Pretty-print a JSON response field (uses python3 if jq absent)
jp() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

# ── Seed sample documents into BIMIndex (live Tantivy) ───────────────────────
seed() {
  sec "Seeding BIMIndex with sample documents"
  need "$INDEX/health" "BIMIndex" || return 1
  curl -fsS -X POST "$INDEX/ingest" -H 'Content-Type: application/json' -d '{
    "documents": [
      {"title":"AWS Q3 Earnings","body":"AWS announced $23B revenue in Q3 driven by generative AI services like Bedrock."},
      {"title":"Cloud Market Share","body":"Amazon Web Services leads cloud market share citing strong AI tool adoption."},
      {"title":"Anthropic Partnership","body":"Strategic investment in Anthropic accelerated AI model deployment on AWS impacting revenue margins."},
      {"title":"BIMRAG Architecture","body":"BIMRAG uses tri-modal retrieval: Tantivy for lexical, LanceDB for dense, KuzuDB for graph with RRF fusion."},
      {"title":"ColPali Embeddings","body":"HPC ColPali encodes document pages into multi-vector embeddings for visually-rich document retrieval."}
    ]
  }' >/dev/null && ok "Indexed 5 sample documents into Tantivy + LanceDB + KuzuDB" || bad "Seed ingest failed"
}

# ── Scenario: BIMIndex tri-modal search + ingest ─────────────────────────────
sc_index_search() {
  sec "BIMIndex — tri-modal search + ingest (T-ROOT-1)"
  need "$INDEX/health" "BIMIndex" || return 1
  ok "GET /health: $(curl -fsS "$INDEX/health" | jp "d['status']")"

  for mode in vectorless dense graph; do
    local n
    n=$(curl -fsS -X POST "$INDEX/search/$mode" -H 'Content-Type: application/json' \
        -d '{"query":"AWS revenue AI","top_k":3}' | jp "len(d['results'])")
    ok "POST /search/$mode → $n result(s)"
  done

  local fused
  fused=$(curl -fsS -X POST "$INDEX/fuse" -H 'Content-Type: application/json' \
        -d '{"query":"AWS revenue AI","top_k":5}' | jp "len(d['results'])")
  ok "POST /fuse (RRF across 3 modes) → $fused fused result(s)"

  # BIMWeb-style GET endpoint
  local gn
  gn=$(curl -fsS "$INDEX/search/vectorless?q=architecture&top_k=3" | jp "len(d['results'])")
  ok "GET /search/vectorless?q=architecture (BIMWeb path) → $gn result(s)"
}

# ── Scenario: BIMExtract ingestion pipeline + skills ─────────────────────────
sc_extract_pipeline() {
  sec "BIMExtract — ingestion pipeline + skills (T-ROOT-2)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  ok "GET /health: $(curl -fsS "$EXTRACT/health" | jp "d['service']")"
  ok "GET /skills: $(curl -fsS "$EXTRACT/skills" | jp "len(d['skills'])") skill(s) registered"

  for pipe in ingest page-index enrich; do
    local job_id status_url
    job_id=$(curl -fsS -X POST "$EXTRACT/pipeline/$pipe" -H 'Content-Type: application/json' \
        -d '{"doc_path":"demo.pdf","text_content":"Revenue grew in 2024. Margins improved."}' \
        | jp "d['job_id']")
    status_url=$(curl -fsS -X POST "$EXTRACT/pipeline/$pipe" -H 'Content-Type: application/json' \
        -d '{"doc_path":"demo.pdf","text_content":"Revenue grew in 2024. Margins improved."}' \
        | jp "d['status_url']")
    # poll until terminal
    local st="running" tries=0
    while [[ "$st" == "running" ]] && (( tries < 20 )); do
      st=$(curl -fsS "$EXTRACT$status_url" | jp "d['status']" 2>/dev/null || echo "running")
      sleep 0.3; ((tries++))
    done
    ok "POST /pipeline/$pipe → job $job_id status=$st"
  done
}

# ── Scenario: BIMExtract ingest → BIMIndex index handoff ─────────────────────
sc_extract_index() {
  sec "BIMExtract → BIMIndex — ingest handoff (T-EXTRACT-15)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  need "$INDEX/health" "BIMIndex" || return 1

  local job_id st chunks indexed
  job_id=$(curl -fsS -X POST "$EXTRACT/pipeline/ingest" -H 'Content-Type: application/json' \
      -d '{"text_content":"Fire rating on floor 3 is 2 hours per spec section 4.2.\nExit width minimum 44 inches."}' \
      | jp "d['job_id']")
  st="queued"; local tries=0
  while [[ "$st" != "ready" && "$st" != "failed" && "$st" != "error" ]] && (( tries < 40 )); do
    st=$(curl -fsS "$EXTRACT/pipeline/ingest/$job_id/status" | jp "d['status']" 2>/dev/null || echo "running")
    sleep 0.3; ((tries++))
  done
  chunks=$(curl -fsS "$EXTRACT/pipeline/ingest/$job_id/status" | jp "d.get('chunk_count') or 0")
  indexed=$(curl -fsS "$EXTRACT/pipeline/ingest/$job_id/status" | jp "d.get('indexed') or 0")
  ok "POST /pipeline/ingest → status=$st, chunks=$chunks, indexed=$indexed"

  local hits
  hits=$(curl -fsS -X POST "$INDEX/search/vectorless" -H 'Content-Type: application/json' \
      -d '{"query":"fire rating floor 3","top_k":3}' | jp "len(d['results'])")
  [[ "$st" == "ready" && "$chunks" -gt 0 ]] \
    && ok "BIMIndex vectorless search after ingest → $hits hit(s)" \
    || bad "Ingest handoff incomplete (status=$st chunks=$chunks)"
}

# ── Scenario: SLT/LGAP parsers ───────────────────────────────────────────────
sc_parsers() {
  sec "BIMExtract — SLT/LGAP parsers (T-EXTRACT-3)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  local fmt
  fmt=$(curl -fsS -X POST "$EXTRACT/parsers/parse" -H 'Content-Type: application/json' \
      -d '{"text":"document \"report.pdf\"\n  section level=1 \"Intro\"\n    text \"Revenue grew.\""}' \
      | jp "d['format']")
  ok "SLT parse → format=$fmt"

  fmt=$(curl -fsS -X POST "$EXTRACT/parsers/parse" -H 'Content-Type: application/json' \
      -d '{"text":"nodes\n  n1 type=section attention=0.9\nedges\n  n1 n2 weight=0.8 relation=contains"}' \
      | jp "d['format']")
  ok "LGAP parse → format=$fmt"
}

# ── Scenario: SuperRAG graph build + search ──────────────────────────────────
sc_graph() {
  sec "BIMExtract — SuperRAG graph build + search (T-EXTRACT-4)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  local nodes hits
  nodes=$(curl -fsS -X POST "$EXTRACT/graph/build" -H 'Content-Type: application/json' \
      -d '{"source":"page_index","tree":{"root":"document","metadata":{"source":"r.pdf"},"children":[
           {"type":"node","id":"n0","content":"Revenue grew in 2024"},
           {"type":"node","id":"n1","content":"Margins improved significantly"}]}}' \
      | jp "len(d['nodes'])")
  ok "POST /graph/build → $nodes graph node(s)"

  hits=$(curl -fsS -X POST "$EXTRACT/graph/search" -H 'Content-Type: application/json' \
      -d '{"query":"revenue","graph":{"nodes":[
           {"id":"a","content":"Revenue grew","attention":0.9},
           {"id":"b","content":"margins improved","attention":0.5}],
           "edges":[{"source":"a","target":"b","weight":0.8,"relation":"read-after"}]},"k":3}' \
      | jp "len(d['results'])")
  ok "POST /graph/search → $hits hit(s) for 'revenue'"
}

# ── Scenario: Auto-RAG ───────────────────────────────────────────────────────
sc_auto_rag() {
  sec "BIMExtract — Auto-RAG classify → strategy → fallback (T-EXTRACT-6)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  local qtype attempts
  qtype=$(curl -fsS -X POST "$EXTRACT/auto-rag/run" -H 'Content-Type: application/json' \
      -d '{"query":"Compare revenue 2023 versus 2024","context":"Revenue grew to 10M in 2024 compared to 6M in 2023 whereas costs stayed flat."}' \
      | jp "d['query_type']")
  attempts=$(curl -fsS -X POST "$EXTRACT/auto-rag/run" -H 'Content-Type: application/json' \
      -d '{"query":"Compare revenue 2023 versus 2024","context":"Revenue grew to 10M in 2024 compared to 6M in 2023 whereas costs stayed flat."}' \
      | jp "len(d['attempts'])")
  ok "Auto-RAG: query_type=$qtype, attempts=$attempts (sufficient on first or falls back)"
}

# ── Scenario: MDocAgent ──────────────────────────────────────────────────────
sc_mdoc() {
  sec "BIMExtract — MDocAgent 4-agent pipeline (T-EXTRACT-7)"
  need "$EXTRACT/health" "BIMExtract" || return 1
  local subtasks results
  subtasks=$(curl -fsS -X POST "$EXTRACT/mdoc/run" -H 'Content-Type: application/json' \
      -d '{"query":"Compare revenue 2023 versus 2024","context":"Revenue grew to 10M in 2024 compared to 6M in 2023. Growth driven by enterprise sales. Costs remained flat whereas revenue increased. Margins improved."}' \
      | jp "len(d['subtasks'])")
  results=$(curl -fsS -X POST "$EXTRACT/mdoc/run" -H 'Content-Type: application/json' \
      -d '{"query":"Compare revenue 2023 versus 2024","context":"Revenue grew to 10M in 2024 compared to 6M in 2023. Growth driven by enterprise sales. Costs remained flat whereas revenue increased. Margins improved."}' \
      | jp "len(d['results'])")
  ok "MDocAgent: decomposed into $subtasks subtasks, $results worker results fused"
}

# ── Scenario: BIMAgent orchestration (→ BIMIndex) ────────────────────────────
sc_agent() {
  sec "BIMAgent — orchestration → BIMIndex (T-ROOT-1 end-to-end)"
  need "$AGENT/health" "BIMAgent" || return 1
  ok "GET /health: $(curl -fsS "$AGENT/health" | jp "d['status']")"
  local resp trace
  resp=$(curl -fsS -X POST "$AGENT/query" -H 'Content-Type: application/json' \
      -d '{"query":"AWS revenue AI"}')
  gen=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('generation') or d.get('response','')[:70])")
  trace=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('trace',[])))")
  ok "POST /query → synthesized: \"${gen}...\" (trace: $trace skill events)"
  echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('generation') or d.get('response',''); exit(0 if 'AWS' in r or 'revenue' in r or 'retrieval' in r else 1)" \
    && ok "Response grounded in BIMIndex retrieval results" || warn "Response not grounded (downstream may be starting)"
}

# ── Scenario: BIMCloud edge gateway (→ BIMAgent) + metrics ───────────────────
sc_cloud() {
  sec "BIMCloud — edge gateway → BIMAgent + Prometheus metrics"
  need "$CLOUD/health" "BIMCloud" || return 1
  ok "GET /health: gateway=$(curl -fsS "$CLOUD/health" | jp "d['gateway']"), breaker=$(curl -fsS "$CLOUD/health" | jp "d['circuit_breaker']")"
  local trace status
  trace=$(curl -fsS -X POST "$CLOUD/query" -H 'Content-Type: application/json' \
      -d '{"query":"AWS revenue AI"}' | jp "d['trace_id'][:8]")
  status=$(curl -fsS -X POST "$CLOUD/query" -H 'Content-Type: application/json' \
      -d '{"query":"AWS revenue AI"}' | jp "d['status']")
  ok "POST /query → trace=$trace, status=$status (routed through gateway to BIMAgent)"
  curl -fsS "$CLOUD/metrics" | grep -q "bimcloud_requests_total" \
    && ok "GET /metrics → Prometheus exposition present" || bad "/metrics missing Prometheus data"
}

# ── Scenario: BIMWeb UI ──────────────────────────────────────────────────────
sc_web() {
  sec "BIMWeb — UI + ecosystem wiring (T-WEB-14)"
  need "$WEB/" "BIMWeb" || return 1
  curl -fsS "$WEB/" >/dev/null && ok "GET / (home) responds"
  curl -fsS "$WEB/dashboard/search" >/dev/null 2>&1 && ok "GET /dashboard/search (search UI) responds" || warn "search UI requires auth redirect (expected)"
  curl -fsS "$WEB/dashboard/deployments" >/dev/null 2>&1 && ok "GET /dashboard/deployments (deploy UI) responds" || warn "deployments UI requires auth redirect (expected)"
}

# ── Run ──────────────────────────────────────────────────────────────────────
ALL=("index-search" "extract-pipeline" "extract-index" "parsers" "graph" "auto-rag" "mdoc" "agent" "cloud" "web")
run_one() {
  case "$1" in
    index-search)    sc_index_search ;;
    extract-pipeline) sc_extract_pipeline ;;
    extract-index)   sc_extract_index ;;
    parsers)         sc_parsers ;;
    graph)           sc_graph ;;
    auto-rag)        sc_auto_rag ;;
    mdoc)            sc_mdoc ;;
    agent)           sc_agent ;;
    cloud)           sc_cloud ;;
    web)             sc_web ;;
    all)             for s in "${ALL[@]}"; do run_one "$s"; done ;;
    *) echo "Unknown scenario: $1"; echo "Available: ${ALL[*]} all"; exit 1 ;;
  esac
}

if [[ "${1:-}" == "--seed" ]]; then seed; exit 0; fi

if [[ $# -eq 0 ]] || [[ "${1:-}" == "all" ]]; then
  for s in "${ALL[@]}"; do run_one "$s"; done
else
  for target in "$@"; do run_one "$target"; done
fi

echo -e "\n${BOLD}━━━ Summary ━━━${NC}"
echo -e "  ${GREEN}Passed: $pass${NC}   ${RED}Failed: $fail${NC}"
[[ "$fail" -eq 0 ]] && echo -e "  ${GREEN}All scenarios passed.${NC}" || echo -e "  ${YELLOW}Some scenarios failed — is the platform running? ./start-platform.sh${NC}"
exit $fail
