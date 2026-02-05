# API Scalability Bottlenecks – Review

This document summarizes scalability and reliability bottlenecks in the ASI Dashboard backend API and recommended mitigations.

---

## Is the service stateless and production-ready?

**Short answer**

- **Stateless for REST:** Yes for the core HTTP API – auth is JWT-only (no server-side sessions). Any instance can serve any REST request. Optional in-memory caches (Zoho portals/projects) are performance-only and can be lost without correctness issues.
- **Stateful components:** The service is **not fully stateless**. Terminal, SSH, VNC, and the file watcher keep in-process state. To run multiple instances behind a load balancer you need **sticky sessions** for WebSocket/terminal/VNC traffic, and the **file watcher** should run on a single designated instance (or be disabled on replicas).
- **Production-ready:** **Not yet** without changes. Critical gaps: no graceful shutdown, pool error kills the process, default JWT secret is unsafe, and DB SSL is off. See the sections below for details.

---

## Statelessness

| Component | Stateful? | Notes |
|-----------|-----------|--------|
| **REST API + JWT** | No | No server-side session store; any instance can validate JWT and serve the request. |
| **Zoho caches** | Soft state | In-memory `portalsCache` / `projectsCache` (TTL 5–10 min). Per-process; improves performance only. Safe to lose on restart or to have different data per instance. |
| **File watcher** | Yes | Holds `watcher`, `processingFiles`; watches a local folder. Multiple instances = duplicate processing. Run on one instance only or disable on replicas. |
| **Terminal (WebSocket)** | Yes | `terminalSessions` Map in `terminal.service.ts`. Session must hit the same process. Requires sticky sessions if scaled horizontally. |
| **SSH service** | Yes | Per-user SSH connections and streams. Same as terminal – sticky sessions required. |
| **VNC (WebSocket)** | Yes | Per-connection TCP + WebSocket. Sticky sessions required. |

**Conclusion:** For **horizontal scaling**, run multiple instances for REST only; route terminal/SSH/VNC to a single instance (or a subset with sticky sessions). Run the file watcher on exactly one instance.

---

## Production readiness – gaps

| Gap | Location | Risk | Recommendation |
|-----|----------|------|----------------|
| **No graceful shutdown** | `index.ts` | SIGTERM/SIGINT kill the process immediately; in-flight requests and WebSocket/SSH connections are cut. | Add handler: stop accepting new connections, drain server, close pool, call `fileWatcherService.stopWatching()`, then `process.exit(0)`. |
| **Pool error → process.exit(-1)** | `config/database.ts` | Any idle client error (e.g. DB restart, network blip) terminates the entire process. | Remove `process.exit(-1)`; log and optionally trigger graceful shutdown or alert. |
| **Default JWT secret** | `auth.middleware.ts`, `auth.routes.ts`, `terminal.routes.ts`, `vnc.routes.ts`, `zoho.routes.ts` | `process.env.JWT_SECRET \|\| 'your-secret-key'` – if env is unset in production, tokens are guessable. | Require `JWT_SECRET` in production (fail startup if `NODE_ENV=production` and missing) or use a strong default only in development. |
| **DB SSL disabled** | `config/database.ts` | `ssl: false` – fine for local Docker; in production, DB traffic should be encrypted. | Use `ssl: true` (or `rejectUnauthorized` and CA) when not local (e.g. when `DATABASE_URL` is not localhost). |
| **Verbose CORS logging** | `index.ts` | `console.log` on every allowed CORS origin can flood logs in production. | Log CORS only in development or at debug level. |
| **Health check scope** | `index.ts` `/health` | Only checks DB. No distinction between “alive” and “ready to take traffic” (e.g. file watcher or Zoho optional). | Optional: add `/ready` that checks DB + any critical deps; use `/health` for liveness, `/ready` for readiness. |

---

## 1. Database connection pool

**Location:** `src/config/database.ts`

**Issue:** The `pg.Pool` is created with no explicit limits:

- No `max` (default 10) – under load, only 10 concurrent DB operations per process.
- No `idleTimeoutMillis` – idle connections can sit in the pool indefinitely.
- No `connectionTimeoutMillis` – slow DB can cause long waits.

**Impact:** Under concurrency, requests queue for a connection; with multiple routes using `pool.connect()` for transactions, the pool can be exhausted and latency can spike.

**Recommendations:**

- Set `max` based on Postgres `max_connections` and number of app instances (e.g. `max: 20` per instance, leave headroom for admin/migrations).
- Set `idleTimeoutMillis` (e.g. 30_000) so idle connections are closed.
- Set `connectionTimeoutMillis` (e.g. 5000) so slow DB fails fast.

```ts
export const pool = new Pool({
  // ...existing options
  max: parseInt(process.env.PG_POOL_MAX || '20', 10),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});
```

---

## 2. Connection leaks on early returns

**Locations:**

- **`src/routes/edaFiles.routes.ts`** – `POST /external/replace-stage`  
  Early returns (400) for missing file, missing params, invalid file type, no data, parse error do **not** call `client.release()`. The client is acquired at the top with `pool.connect()` but only released on success or in the `catch` block.

- **`src/routes/project.routes.ts`** – `GET /:projectIdOrName/blocks-experiments`  
  Multiple `return res...` paths call `client.release()` before returning, but if any new return is added without `client.release()`, the leak will reappear. Using a single `try/finally` that always releases is safer.

**Impact:** Each leaked connection reduces the effective pool size; under load or repeated validation errors, the pool can be exhausted and the API can hang or return 500s.

**Recommendations:**

- In **edaFiles** replace-stage: wrap the handler in `try/finally` and call `client.release()` in `finally` for every exit path (and avoid starting a transaction until after validation so ROLLBACK isn’t needed on early returns).
- In **project.routes** blocks-experiments: use one `try { ... } finally { client.release(); }` and avoid releasing inside multiple branches.

---

## 3. No pagination on project list

**Location:** `src/routes/project.routes.ts` – `GET /api/projects`

**Issue:** The main project list query has no `LIMIT` or `OFFSET`. It loads all projects (with domains, latest run status, last run time) for the user in one response. When `includeZoho=true`, Zoho projects are also fetched and merged.

**Impact:** As project count grows, response size and query time grow. Large JSON payloads and long DB time can increase memory and latency and risk timeouts.

**Recommendations:**

- Add optional query params, e.g. `limit` (default 50, max 200) and `offset` (or `page`/`pageSize`).
- Apply `LIMIT`/`OFFSET` in the main SQL and return something like `{ projects, total, limit, offset }` (total from a separate `COUNT(*)` or window function, depending on DB version).
- Keep Zoho merge logic but consider applying the same logical “page” (e.g. same limit) when merging local + Zoho so the combined list is bounded.

---

## 4. Sequential queries on dashboard stats

**Location:** `src/routes/dashboard.routes.ts` – `GET /api/dashboard/stats`

**Issue:** Six independent queries run one after another:

1. Total chips  
2. Chips by status  
3. Total designs  
4. Designs by status  
5. Recent chips (LIMIT 5)  
6. Recent designs (LIMIT 5)  

**Impact:** Latency is the sum of six round-trips. Under load, this multiplies with connection pool contention.

**Recommendation:** Run the independent queries in parallel with `Promise.all` (and optionally a single “stats” query that returns aggregates in one round-trip if the schema allows).

---

## 5. Per-request schema check (projects list)

**Location:** `src/routes/project.routes.ts` – `GET /api/projects`

**Issue:** For role `engineer`, the code runs a one-off `information_schema.tables` check to see if `user_projects` exists, on every request.

**Impact:** Extra round-trip and lock access to `information_schema` on every project list call for engineers.

**Recommendation:** Resolve this once at startup (or when DB is known to have been migrated) and store the result (e.g. a boolean or feature flag). Use that cached value in the request path instead of querying `information_schema` per request.

---

## 6. Heavy project list query (correlated subqueries)

**Location:** `src/routes/project.routes.ts` – main `SELECT` for `GET /api/projects`

**Issue:** For each project row the query uses correlated subqueries for:

- `latest_run_status` (subquery on `stages` → `runs` → `blocks`)
- `last_run_at` (same kind of subquery)

With many projects, this can be expensive and sensitive to missing indexes.

**Impact:** Slower list endpoint as data grows; risk of timeouts for users with many projects.

**Recommendations:**

- Add pagination (see §3) to reduce rows per request.
- Consider replacing correlated subqueries with a single join to a derived table or lateral join that computes “latest run per project” once (e.g. `DISTINCT ON (project_id)` or window function), then join to `projects`.
- Ensure indexes exist on `blocks(project_id)`, `runs(block_id)`, `stages(run_id)`, and `stages(timestamp DESC)` (or equivalent for the “latest” logic).

---

## 7. Zoho integration in request path

**Location:** `src/routes/project.routes.ts` – `GET /api/projects` when `includeZoho=true`

**Issue:** When Zoho is included, the handler calls external Zoho APIs (portals, projects) and then runs several batch DB queries (mappings, run dirs, export status). Zoho calls are cached in `zoho.service` (e.g. 5–10 min TTL), but the first request or after cache expiry is slow and can fail due to network or Zoho rate limits.

**Impact:** Project list latency and failure rate depend on an external system; a Zoho outage or rate limit can make the whole list endpoint slow or failing.

**Recommendations:**

- Keep and consider shortening cache TTL for “list” use cases if data freshness allows.
- Consider making Zoho data optional and loaded asynchronously (e.g. return local projects first, then stream or poll for Zoho projects) so the main list is not blocked by Zoho.
- Add timeouts and retries with backoff for Zoho HTTP calls; on failure, return local projects and a flag like `zohoUnavailable: true` instead of failing the whole request.

---

## 8. Large route and transaction files

**Location:** `src/routes/project.routes.ts` (~2.7k+ lines), `src/services/qms.service.ts` (large number of `pool.connect()` usages)

**Issue:** Single very large files with many handlers and branches increase the chance of inconsistent patterns (e.g. missing `client.release()` or ROLLBACK) and make it harder to optimize or add caching per endpoint.

**Recommendation:** Split by domain (e.g. project list vs project detail vs blocks-experiments) into smaller modules and shared helpers (e.g. “resolve project by id/name”, “check access”) so connection and transaction handling can be centralized (e.g. a small wrapper that always releases in `finally`).

---

## 9. EDA files list: count query duplication

**Location:** `src/routes/edaFiles.routes.ts` – list endpoint

**Issue:** The same filters are applied twice: once in the main query (with LIMIT/OFFSET) and again in a separate `COUNT(DISTINCT s.id)` query. Filter logic is duplicated in two large query strings.

**Impact:** Two heavy queries per request; any change to filters must be done in two places (risk of drift and bugs).

**Recommendation:** Where possible, use a single query that returns both the page of rows and the total (e.g. window function `COUNT(*) OVER ()`) so filter logic lives in one place and round-trips are reduced. If the DB or query shape makes that awkward, at least extract filter building into a shared function used by both the data and count queries.

---

## 10. No rate limiting or request timeouts

**Location:** `src/index.ts` (global), no per-route limits

**Issue:** There is no application-level rate limiting or per-route timeout. Long-running or abusive clients can hold connections and DB clients.

**Impact:** One heavy or buggy client can degrade the API for everyone; long-running Zoho or DB calls can hold resources.

**Recommendations:**

- Add a global or per-route request timeout (e.g. 30–60 s for normal endpoints, longer only where required).
- Add rate limiting (e.g. by IP or API key) for expensive or external endpoints (e.g. project list with Zoho, EDA replace-stage, auth).

---

## Summary table

| Area                    | Severity | Effort | Notes                                      |
|-------------------------|----------|--------|--------------------------------------------|
| Pool config             | High     | Low    | Set max, idleTimeout, connectionTimeout    |
| Connection leaks       | High     | Low    | edaFiles replace-stage; use try/finally    |
| Project list pagination | High     | Medium | Add limit/offset and total                 |
| Dashboard parallel      | Medium   | Low    | Promise.all for stats                      |
| user_projects check     | Medium   | Low    | Cache at startup                           |
| Project list query      | Medium   | Medium | Pagination + simplify subqueries/indexes   |
| Zoho in request path    | Medium   | Medium | Cache, timeouts, optional/async Zoho       |
| Route/service size      | Low      | Medium | Split project/qms for maintainability      |
| EDA count duplication   | Low      | Medium | One query or shared filter builder         |
| Rate limit / timeouts   | Medium   | Medium | Global or per-route timeout + rate limit   |

Addressing pool configuration and connection leaks first will improve stability under load; adding pagination and parallelizing dashboard stats will improve latency and scalability of the most common flows.
