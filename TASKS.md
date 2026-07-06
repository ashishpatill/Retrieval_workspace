
> **Layout (2026-07):** Python backends are consolidated under `bimrag-backend/services/{bimindex,bimextract,bimagent,bimcloud}`. Root `docker-compose.yml` and `start-platform.sh` use those paths.
# BIMRAG Ecosystem — Cross-Repository Task List

This file tracks cross-repo coordination tasks. Each repo has its own `TASKS.md` for per-repo work.
Before starting any task, read `ROUTING.md` to select the correct model tier.

**Last updated: 2026-07-07** — Root `docker-compose.yml` for 4 Python services; BIMWeb E2E auth bypass, Upstash rate limiter, Playwright CI (smoke/a11y/platform-api); `API_CONTRACT.md` at workspace root. Platform orchestration via `start-platform.sh` + `run-scenarios.sh` (multi-arg).

---

## Per-Repo Status Summary

| Repo | TASKS.md items | Done | Status |
|------|---------------|------|--------|
| BIMAgent | 7 + integration | 8 | ✅ 100% — cross-repo tools verified live; 13 tests pass |
| BIMCloud | 6 + 2 optional | 8 | ✅ 100% + Prometheus metrics + multi-region deploy; 31 tests pass |
| BIMExtract | 14 + T-ROOT-2 | 15 | ✅ 100% — server.py live (pipelines, parsers, graph, auto-rag, mdoc); 154 tests pass |
| BIMIndex | 10 + T-ROOT-1 | 11 | ✅ 100% — server.py live (tri-modal search + fuse + ingest); 188 tests pass |
| BIMWeb | 14 | 14 | ✅ 100% — E2E bypass, Upstash rate limit, Playwright CI, a11y; 197 tests pass |

**Major session milestones (2026-06-25 to 2026-06-26)**:
- T-ROOT-5 complete: Tantivy, LanceDB, KuzuDB, Neo4j live in BIMIndex venv
- BIMExtract 4 missing modules: `src/parsers/` (SLT/LGAP), `src/graph/` (SuperRAG), `src/auto_rag/`, `src/agents/` (MDocAgent) — 93 new tests
- BIMWeb T-WEB-14: search UI + deployments UI wired to BIMAgent/BIMIndex/BIMCloud with unified error handling — 15 new tests
- BIMCloud: optional `/metrics` Prometheus endpoint + multi-region Cloud Run terraform — 13 new tests
- CI/CD pipelines + `pyproject.toml` added to BIMAgent and BIMExtract
- **T-ROOT-1**: BIMIndex FastAPI server (`BIMIndex/server.py`) — tri-modal `/search/{vectorless,dense,graph}` (GET+POST), `/fuse`, `/ingest` (live Tantivy), `/stats`, `/health`. Runs on port 8001.
- **T-ROOT-2**: BIMExtract FastAPI server (`BIMExtract/server.py`) — async `/pipeline/{ingest,page-index,enrich}` with status polling, `/parsers/parse` (SLT/LGAP auto-route), `/graph/build`+`/graph/search`, `/auto-rag/run`, `/mdoc/run`, `/skills`, `/health`. Runs on port 8200.
- **BIMAgent integration**: `run_workflow` now synthesizes a grounded answer from BIMIndex snippets (no longer empty without an API key); `config.py` set `extra="ignore"` so cross-repo env vars don't crash pydantic.
- **Platform orchestration**: `start-platform.sh` (one-command launch of all 5 services, health checks, per-service logs, graceful shutdown, `--demo` mode) + `run-scenarios.sh` (26 end-to-end checks exercising all 9 feature areas across all repos).

---

## T-ROOT-1: BIMAgent → BIMIndex Tool Calls — **DONE**

**Status**: ✅ `BIMIndex/server.py` live, verified with 26 end-to-end scenarios.

- FastAPI server wraps `retrieval_tools.py` (Tantivy BM25, LanceDB vector, KuzuDB graph, RRF fusion)
- Endpoints: `GET/POST /search/{vectorless,dense,graph}`, `POST /fuse`, `POST /ingest` (live Tantivy indexing), `GET /stats`, `GET /health`
- Started by `start-platform.sh` on port 8001 (uses `.venv/bin/python` for live DB access)
- BIMAgent's `BIMIndexSearchSkill` calls these endpoints with retries + exponential backoff
- Verified: `run-scenarios.sh` — 5 index-search scenarios pass (vectorless, dense, graph, fuse, BIMWeb path)

**Verification**: `./start-platform.sh --demo` → all BIMIndex scenarios pass (seed → search → fuse → ingestion).

---

## T-ROOT-2: BIMAgent → BIMExtract Tool Calls — **DONE**

**Status**: ✅ `BIMExtract/server.py` live, verified with 26 end-to-end scenarios.

- FastAPI server wraps all BIMExtract research modules: parsers, pipelines, SuperRAG, Auto-RAG, MDocAgent
- Endpoints: `POST /pipeline/{ingest,page-index,enrich}` (async with status polling), `POST /parsers/parse` (SLT/LGAP auto-route), `POST /graph/build` + `POST /graph/search`, `POST /auto-rag/run`, `POST /mdoc/run`, `GET /skills`, `GET /health`
- Started by `start-platform.sh` on port 8200
- BIMAgent's `BIMExtractSkill` triggers and polls pipeline endpoints
- Verified: `run-scenarios.sh` — 9 extract scenarios pass (pipeline, parsers, graph, auto-rag, mdoc)

**Verification**: `./start-platform.sh --demo` → all BIMExtract scenarios pass (ingestion → parse → graph → auto-rag → mdoc).

---

## T-ROOT-3: BIMCloud → BIMAgent Traffic Routing — **DONE**

**Status**: ✅ `BIMCloud/src/gateway/router.py` (161 lines) with `CircuitBreaker` and `EdgeRouter`.

**Done**:
- `EdgeRouter` POSTs to `${BIMAGENT_URL}/query` with `X-Trace-ID` and `X-Forwarded-For` headers
- Circuit breaker state machine (closed/open/half-open)
- 7 tests in `BIMCloud/tests/test_router.py`

**Verification**: Query flows client → BIMCloud → BIMAgent → response with full trace.

---

## T-ROOT-4: BIMWeb → Ecosystem Integration — **DONE**

**Status**: ✅ `src/lib/api-clients.ts` rewritten with unified `EcosystemError`/`fetchWithTimeout`; `BIMCloudClient` aligned to the real `POST /query` gateway. Search UI (`src/app/dashboard/search/`) calls BIMAgent + BIMIndex; Deployments UI (`src/app/dashboard/deployments/`) calls BIMCloud. Sidebar wired. 15 new integration/smoke tests; `eslint` + `tsc --noEmit` clean.

**Dependencies**: T-ROOT-1, T-ROOT-2, T-ROOT-3 (all substantially done).

**Verification**: All 3 integrations callable from the BIMWeb UI in a single session (live backends required for end-to-end).

---

## T-ROOT-5: BIMIndex 3× Live DB Integrations — **DONE** ✅

**Status**: ✅ All 4 live backends installed and tested.

**Done**:
- `tantivy==0.26.0` installed; `src/backends/tantivy_index.py` updated to v0.26 API
- `lancedb==0.25.3` + `pyarrow==24.0.0` installed; `LanceDBIndex` with MUVERA IVF index
- `kuzu==0.11.3` installed; `KuzuGraph` updated to v0.11 API (file path, persistent connection)
- `neo4j==6.2.0` installed; `Neo4jGraph` with mocked tests
- `pyproject.toml` updated to declare all 4 packages as runtime deps
- `retrieval_tools.py` rewritten to use live backends with mock fallback
- 43 new live integration tests + 12 retrieval_tools tests
- Total: **188 tests pass + 9 skipped** (vs. mostly skipped before)

**Verification**: `PYTHONPATH=. pytest tests/ -v` — 188 passed, 9 skipped.

---

## Cross-Repo Priority Order

1. ~~**T-ROOT-5** (BIMIndex live DBs)~~ ✅ **DONE**
2. ~~**T-EXTRACT-3/4/6/7** (4 missing BIMExtract modules)~~ ✅ **DONE** (154 tests pass)
3. ~~**T-WEB-14 / T-ROOT-4** (BIMWeb ecosystem wiring)~~ ✅ **DONE** (21 tests pass)
4. ~~**T-ROOT-2** (BIMExtract live endpoints)~~ ✅ **DONE** (server.py on port 8200, 9 scenarios verified)
5. ~~**T-ROOT-1** (BIMIndex live endpoints)~~ ✅ **DONE** (server.py on port 8001, 5 scenarios verified)
6. ~~**T-WEB-1** (BIMWeb expanded test coverage) + **T-WEB-13** (API key validation)~~ ✅ **DONE**
7. **Push BIMWeb migration `0002`** to Neon (human approval)
8. **BIMWeb `next build` unblock** (pre-existing lightningcss ARM-vs-x64 mismatch)

## T-ROOT-6: Docker Compose + E2E CI — **DONE**

**Status**: ✅ Root `docker-compose.yml` builds BIMIndex, BIMExtract, BIMAgent, BIMCloud (ports 8001/8200/8000/8080).

- Dockerfiles: `BIMIndex/Dockerfile` (target `api`, port 8001), `BIMExtract/Dockerfile`, `BIMAgent/Dockerfile` (excludes `google-antigravity`)
- BIMWeb: `src/lib/session.ts` (`E2E_TEST_BYPASS`), `src/lib/rate-limit.ts` (Upstash + in-memory)
- Playwright: `platform-api.spec.ts`, `a11y.spec.ts`, updated `playwright.yml` (smoke + ecosystem jobs)

**Verification**: `docker compose up -d` → `ECOSYSTEM_E2E=true pnpm exec playwright test tests/e2e/platform-api.spec.ts`

## Parallel Dispatch Rules (Updated)

| Batch | Tasks | Parallel Agents |
|-------|-------|-----------------|
| ~~T-EXTRACT-3, 4, 6, 7~~ | ~~SLT/LGAP, SuperRAG, Auto-RAG, MDocAgent~~ | ✅ Done (4× Pro) |
| ~~T-WEB-14~~ | ~~Search UI + deployment UI~~ | ✅ Done (1× GLM-5.2) |
| ~~T-ROOT-2~~ | ~~BIMExtract FastAPI server~~ | ✅ Done (1× Flash) |
| ~~T-ROOT-1~~ | ~~BIMIndex FastAPI server~~ | ✅ Done (1× Flash) |
| T-WEB-1 (test expansion) | Unit tests for rbac, sharing, storage, api-clients, ifc/parser | 5× Flash (parallel) |

## Security Rules

1. **Never send API keys, secrets, or credentials to any cloud model.** Use local Nanbeige-3B (Ollama).
2. **Payment code requires Pro verification.** Stripe, Dodo Payments: Flash writes, Pro reviews.
3. **AuthZ/RBAC code requires Pro verification.** Team invites, role enforcement.
4. **Exposed credentials**: BIMWeb `.env.local` contains real Kinde secret + Neon DB URL. Use local Nanbeige-3B for any task involving these files.
