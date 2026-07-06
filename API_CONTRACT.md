# BIMRAG Ecosystem — API Contract

Shared HTTP contracts between BIMWeb, BIMCloud, BIMAgent, BIMIndex, and BIMExtract.

## Ports (local)

| Service | Port | Base URL |
|---------|------|----------|
| BIMWeb | 3000 | `http://localhost:3000` |
| BIMAgent | 8000 | `http://localhost:8000` |
| BIMIndex | 8001 | `http://localhost:8001` |
| BIMExtract | 8200 | `http://localhost:8200` |
| BIMCloud | 8080 | `http://localhost:8080` |

Start all: `./start-platform.sh` · Verify: `./run-scenarios.sh all`

---

## BIMCloud (edge gateway)

### `GET /health`
```json
{ "gateway": "healthy", "agent": "healthy", "circuit_breaker": "closed", "region": "local", "regions": ["local"] }
```

### `POST /query`
Request: `{ "query": string, "user_id"?: string }`  
Response: `{ "result": object, "trace_id": string, "latency_ms": number, "status": "ok" }`  
Streaming: `POST /query?stream=true` → SSE proxy to BIMAgent.

### `GET /metrics`
Prometheus text format (`bimcloud_*` + `http_requests_total` compatibility aliases).

---

## BIMAgent (orchestrator)

### `GET /health`
`{ "status": "ok" }`

### `POST /query`
Request: `{ "query": string }`  
Response: `{ "query", "response", "trace": string[], "session_id" }`  
Streaming: `POST /query?stream=true` → SSE with `type: trace|result`.

---

## BIMIndex (tri-modal retrieval)

### `GET /health`
`{ "status": "ok", "service": "bimindex", "modes": ["vectorless","dense","graph"] }`

### `POST /search/{vectorless|dense|graph}`
Request: `{ "query": string, "top_k"?: number }`  
Response: `{ "results": Hit[], "mode": string, "query": string, "total": number }`

### `POST /fuse`
RRF fusion across all three modes.

### `POST /ingest`
Request: `{ "documents": [{ "title": string, "body": string }] }`  
Response: `{ "status": "ok"|"partial", "indexed": number, "backends": { tantivy, lancedb, kuzudb } }`

### `GET /stats`
Per-backend availability and document counts.

---

## BIMExtract (ingestion)

### `GET /health`
Service status + poppler/GPU/runtime checks.

### `GET /skills`
`{ "skills": [{ "name", "description" }] }`

### `POST /pipeline/{ingest|page-index|enrich}`
Request: `{ "doc_path"?: string, "text_content"?: string, ... }`  
Response: `{ "job_id", "status_url", "status": "queued" }`

### `GET /pipeline/{name}/{job_id}/status`
Terminal statuses: `ready`, `completed`, `failed`, `error`.  
Ingest success includes `chunk_count`, `indexed` (BIMIndex handoff).

---

## Job lifecycle (Documents UI)

`queued` → `parsing` → `indexing` → `ready` | `failed`

---

## Environment variables

| Variable | Used by | Default |
|----------|---------|---------|
| `NEXT_PUBLIC_BIMAGENT_URL` | BIMWeb | `http://localhost:8000` |
| `NEXT_PUBLIC_BIMINDEX_URL` | BIMWeb | `http://localhost:8001` |
| `NEXT_PUBLIC_BIMEXTRACT_URL` | BIMWeb | `http://localhost:8200` |
| `NEXT_PUBLIC_BIMCLOUD_URL` | BIMWeb | `http://localhost:8080` |
| `BIMAGENT_URL` | BIMCloud | `http://localhost:8000` |
| `BIMINDEX_URL` | BIMAgent, BIMExtract | `http://localhost:8001` |
| `BIMEXTRACT_URL` | BIMAgent | `http://localhost:8200` |
| `DENSE_EMBEDDING_BACKEND` | BIMIndex | `hashed` (set `colqwen2.5` for GPU) |
| `DEMO_MODE` | BIMIndex | `true` |

## Repository layout

Service implementations: `bimrag-backend/services/*`. Port and HTTP contracts unchanged.
