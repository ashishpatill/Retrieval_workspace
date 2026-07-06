# BIMRAG Ecosystem — Cross-Repository Model Routing

This document defines model routing across all 5 repos of the BIMRAG ecosystem.
Each repo has its own `ROUTING.md` with per-task assignments. This file covers
cross-repo coordination and shared infrastructure.

**Last updated: 2026-06-26** — All cross-repo tasks complete. T-ROOT-1 (BIMIndex server) and T-ROOT-2 (BIMExtract server) live and verified through `start-platform.sh --demo`. Platform orchestration enables one-command start of all 5 services with 26 end-to-end scenarios.

## RouteFusion Offload Scoring (Universal)

```
offload_score = (blast_radius × 3 + ambiguity × 2 + quality_sensitivity × 2) / verification_strength
```

| Axis | 1 | 2 | 3 |
|------|---|---|---|
| blast_radius | local | module | system |
| ambiguity | low | medium | high |
| quality_sensitivity | low | medium | high |
| verification_strength | weak (1) | moderate (2) | strong (3) |

| Score | Tier | Action | Example |
|-------|------|--------|---------|
| < 3 | free | Free model | Trivial formatting, session titles |
| 3–5 | flash | DeepSeek V4 Flash alone | SDK wiring, tests, docs, CI/CD |
| 5–7 | flash→pro | Flash writes + Pro verifies | Payment code, RBAC, eval metrics |
| > 7 | pro | DeepSeek V4 Pro from scratch | Cross-repo arch, ML research, novel features |

## Provider Setup

| Provider | How to access | Models |
|----------|--------------|--------|
| **OpenCode Zen** | Built-in (free tier) | `opencode/deepseek-v4-flash-free`, `opencode/mimo-v2.5-free`, `opencode/nemotron-3-ultra-free`, `opencode/north-mini-code-free` |
| **OpenRouter** | Connected via opencode (`/connect` → OpenRouter) | All `openrouter/...` models |
| **Local Ollama** | `ollama pull <model>` | `nanbeige4.1-3b`, `phi-4`, `qwen3.5-9b` (offline, private) |

> **OpenRouter key status**: Already configured in opencode. If API calls fail, run `/connect` → OpenRouter to re-add the key.

## Available Models (Provider-Prefixed IDs)

| Model | Model ID (use this) | Cost/M in | Context | License | Role |
|-------|---------------------|-----------|---------|---------|------|
| DeepSeek V4 Flash *(free)* | `opencode/deepseek-v4-flash-free` | $0 | 1M | MIT | Free tier: trivial/docs via Zen |
| DeepSeek V4 Flash *(paid)* | `openrouter/deepseek/deepseek-v4-flash` | $0.09 | 1M | MIT | Bounded implementation, cheap throughput |
| DeepSeek V4 Pro | `openrouter/deepseek/deepseek-v4-pro` | $0.435 | 1M | MIT | Planning, debugging, review, architecture |
| Qwen3 Coder Plus | `openrouter/qwen/qwen3-coder-plus` | $0.65 | 1M | Apache 2.0 | Complex coding (I.90), tool calling (TC.92) |
| Qwen3.7 Plus | `openrouter/qwen/qwen3.7-plus` | $0.32 | 1M | Apache 2.0 | Strongest Apache 2.0 all-rounder |
| GLM-5.2 | `openrouter/z-ai/glm-5.2` | $0.15 | 1M | MIT | Cross-repo, 1M context reading |
| Kimi K2.7 | `openrouter/moonshotai/kimi-k2.7-code` | $0.612 | 262K | Proprietary | Repo analysis, review (R.85) |
| MiMo V2.5 Pro | `openrouter/xiaomi/mimo-v2.5-pro` | $0.435 | 1M | Proprietary | Terminal/debug loops (TC.90) |
| Nex N2 Pro | `openrouter/nex-agi/nex-n2-pro` | $0.50 | 262K | Proprietary | Fast impl, Flash fallback |
| Gemini 3.5 Flash | `openrouter/google/gemini-3.5-flash` | $0.0375 | 1M | Proprietary | Max cheap throughput |
| Phi-4 | `openrouter/microsoft/phi-4` | $0.07 | 16K | MIT | Small code tasks, tests |
| Codestral 2508 | `openrouter/mistralai/codestral-2508` | $0.30 | 256K | MS Research | Code generation specialist |
| Llama 3.3 70B | `openrouter/meta-llama/llama-3.3-70b-instruct` | $0.10 | 131K | Llama 3 | Research features, ML reasoning |
| Qwen3 Coder *(free)* | `openrouter/qwen/qwen3-coder:free` | $0 | 1M | Apache 2.0 | Free code generation via OpenRouter |
| Gemma 4 31B *(free)* | `openrouter/google/gemma-4-31b-it:free` | $0 | 262K | Apache 2.0 | Free generalist via OpenRouter |
| Nanbeige 4.1 3B | *(local Ollama)* | $0 | — | Apache 2.0 | Private work, sensitive material |

## Cross-Repo Task Routing (Current Active Tasks)

| Task | Offload | Tier | Model(s) | Scope | Status |
|------|---------|------|----------|-------|--------|
| T-ROOT-5: BIMIndex live DBs (Tantivy/LanceDB/KuzuDB/Neo4j) | 7.0 | flash→pro | **Qwen3 Coder Plus** × 3 parallel + 1× V4 Pro verify | 1 repo, 4 subsystems | ✅ **DONE** (43 new live tests, 188 pass) |
| T-ROOT-2: BIMAgent → BIMExtract live endpoints | 7.0 | flash | **DeepSeek V4 Flash** | 2 repos | ✅ **DONE** (`BIMExtract/server.py` — pipelines, parsers, graph, auto-rag, mdoc) |
| T-ROOT-1: BIMIndex live endpoints (FastAPI server) | 7.0 | flash | **DeepSeek V4 Flash** | 1 repo | ✅ **DONE** (`BIMIndex/server.py` — tri-modal search + fuse + ingest) |
| T-ROOT-3: BIMCloud → BIMAgent routing | 10.5 | pro | **DeepSeek V4 Pro** | 2 repos | ✅ DONE |
| T-ROOT-4: BIMWeb → ecosystem wiring | 10.5 | pro | **DeepSeek V4 Pro** or **GLM-5.2** | 3 repos | ✅ **DONE** (GLM-5.2: search UI + deploy UI wired) |
| T-EXTRACT-3: SLT/LGAP parser | 8.0 | pro | **DeepSeek V4 Pro** | 1 repo | ✅ **DONE** |
| T-EXTRACT-4: SuperRAG graph | 8.0 | pro | **DeepSeek V4 Pro** | 1 repo | ✅ **DONE** |
| T-EXTRACT-6: Auto-RAG | 9.0 | pro | **DeepSeek V4 Pro** | 1 repo | ✅ **DONE** |
| T-EXTRACT-7: MDocAgent | 8.0 | pro | **DeepSeek V4 Pro** | 1 repo | ✅ **DONE** |
| T-AGENT: CI/CD | 7.0 | flash | **DeepSeek V4 Flash** | 1 repo | ✅ **DONE** (13 tests pass) |
| T-EXTRACT: CI/CD + pyproject.toml | 7.0 | flash | **DeepSeek V4 Flash** | 1 repo | ✅ **DONE** (61 tests pass) |
| T-WEB-1: Expand test coverage | 7.0 | flash | **DeepSeek V4 Flash** × 5 parallel | 1 repo | Sparse tests |
| T-INDEX-RETRIEVAL: Wire live backends to retrieval_tools.py | 7.0 | flash | **DeepSeek V4 Flash** | 1 repo | ✅ **DONE** (12 new tests) |
| **Platform orchestration**: `start-platform.sh` + `run-scenarios.sh` | 7.0 | flash | **DeepSeek V4 Flash** | 5 repos | ✅ **DONE** (26 end-to-end scenarios pass) |
| **BIMAgent integration**: `run_workflow` synthesis, `config.py` fix | 7.0 | flash | **DeepSeek V4 Flash** | 1 repo | ✅ **DONE** (grounded answers without API key) |

## Parallel Dispatch Rules (Updated for Current State)

| Batch | Tasks | Parallel Agent Assignments |
|-------|-------|---------------------------|
| T-ROOT-5 (BIMIndex live DBs) | Tantivy, LanceDB, KuzuDB package install + wire | 3× `openrouter/qwen/qwen3-coder-plus` + 1× `openrouter/deepseek/deepseek-v4-pro` verify |
| T-EXTRACT 4 missing modules | SLT/LGAP, SuperRAG, Auto-RAG, MDocAgent | 4× `openrouter/deepseek/deepseek-v4-pro` (parallel) |
| T-WEB-1 (test expansion) | rbac, sharing, storage, api-clients, ifc/parser | 5× `openrouter/deepseek/deepseek-v4-flash` (parallel) |
| CI/CD additions | BIMAgent, BIMExtract | 2× `openrouter/deepseek/deepseek-v4-flash` (parallel) |

## Security Rules

1. **Never send API keys, secrets, or credentials to any cloud model.** Use local Nanbeige-3B (Ollama).
2. **Payment code requires Pro verification.** Stripe, Dodo Payments: Flash writes, Pro reviews.
3. **AuthZ/RBAC code requires Pro verification.** Team invites, role enforcement.
4. **Exposed credentials — special handling**:
   - `BIMWeb/.env.local` contains real `KINDE_CLIENT_SECRET` and `DATABASE_URL` (Neon). Use local Nanbeige-3B for any task involving this file.
   - `BIMAgent/.env` contains `OPENAI_API_KEY=your_key_here` (placeholder, safe).

## Cross-Repo Task List

**Read `TASKS.md` (root level) for detailed specs and implementation steps for all cross-repo tasks.**
Each repo also has its own `TASKS.md` with per-repo task details.

## Quick Start

```bash
# Set up API keys
export DEEPSEEK_API_KEY=sk-...
export OPENROUTER_API_KEY=sk-...

# Or use local models
ollama pull nanbeige4.1-3b
ollama pull phi-4

# Each repo has its own ROUTING.md with per-gap assignments
```

## Per-Repo Status Snapshot

| Repo | Critical Path | Best-Fit Model |
|------|---------------|----------------|
| BIMAgent | ✅ All done — cross-repo tools verified live, `run_workflow` synthesizes grounded answers | DeepSeek V4 Flash |
| BIMCloud | ✅ All done + optional Prometheus metrics + multi-region deploy | DeepSeek V4 Flash |
| BIMExtract | ✅ 100% — all 14 tasks + T-ROOT-2 server live (pipelines, parsers, graph, auto-rag, mdoc on port 8200) | DeepSeek V4 Pro (modules); DeepSeek V4 Flash (server) |
| BIMIndex | ✅ 100% — all 10 tasks + T-ROOT-1 server live (tri-modal search on port 8001) | Qwen3 Coder Plus (DBs); DeepSeek V4 Flash (server) |
| BIMWeb | T-WEB-13 (API keys); T-WEB-1 (test coverage); `next build` blocked by lightningcss ARM mismatch | DeepSeek V4 Flash (tests, API); DeepSeek V4 Pro (ecosystem wiring) |
