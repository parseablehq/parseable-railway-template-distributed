# Deploy and Host Parseable (Distributed) with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/parseable-distributed)

[Parseable](https://parseable.com) is an open source telemetry data lake. This template deploys Parseable in **distributed mode** on [Railway](https://railway.com) with one query node and one ingest node, backed by a shared Railway Bucket (S3-compatible object storage) and persistent volumes for each node's staging directory.

For the simpler single-node deployment, see the [standalone template](https://railway.com/deploy/parseable-1).

## About Distributed Parseable

Distributed mode separates the ingestion path from the query path:

- **Ingest nodes** receive incoming events from log shippers (Fluent Bit, OpenTelemetry Collector, direct HTTP) and write them to object storage.
- **Query nodes** serve the UI, the SQL API, and read events back from object storage.

Both nodes share the same Bucket and the same admin credentials. The query node discovers active ingestors through a manifest in the Bucket, where each ingestor registers its `P_INGESTOR_ENDPOINT`.

## Architecture

```
Log clients (HTTPS) ─────► parseable-ingest (public domain)
                           │  P_MODE=ingest
                           │  Volume: /data/staging
                           │
                           │ (registered via .parseable/.parseable.json)
                           ▼
                   ┌──────────────────────┐
                   │   Railway Bucket     │
                   │  (shared S3 store)   │
                   └──────────┬───────────┘
                              ▲
                              │
                              │ private network
                              │
UI / SQL (HTTPS) ────► parseable-query (public domain)
                       │  P_MODE=query
                       │  Volume: /data/staging
```

## Common Use Cases

- **High-volume log ingestion** — scale the ingest path independently of query traffic
- **Production OpenTelemetry backend** — receive traces, logs, and metrics on the ingest endpoint while keeping query traffic isolated
- **Separation of concerns** — log shippers point at the ingest URL, dashboards and operators point at the query URL
- **Drop-in replacement for heavyweight log backends** — replace stacks like ELK with a smaller, S3-native cluster

## Dependencies for Distributed Parseable Hosting

- A Railway account on a paid plan (Buckets, volumes, and multiple services require it)
- Railway Bucket for shared S3-compatible storage (provisioned automatically)
- Two Railway persistent volumes mounted at `/data/staging` on each node (provisioned automatically)

### Deployment Dependencies

- [Parseable Docker Image](https://hub.docker.com/r/parseable/parseable) — `parseable/parseable:edge`
- [Railway Buckets](https://docs.railway.com/reference/buckets) — S3-compatible storage provisioned within Railway
- [Railway Volumes](https://docs.railway.com/reference/volumes) — persistent disk attached to each Parseable service
- [Parseable Documentation](https://www.parseable.com/docs) — configuration reference and API docs

### Why Distributed Mode on Railway?

Railway provides one-click deployment with built-in S3-compatible storage via Buckets, persistent volumes, automatic health checks, and public HTTPS URLs for every service. Distributed Parseable benefits from:

- Independent scaling of ingest and query nodes (add more ingestors later from the Railway dashboard)
- Public HTTPS endpoints for both ingest (clients) and query (UI/SQL)
- Private networking between nodes via Railway's `RAILWAY_PRIVATE_DOMAIN`, so cluster traffic never leaves Railway
- Shared Bucket credentials injected at deploy time with zero manual configuration

### Storage Layout

Distributed Parseable on Railway uses three storage resources, all managed by the platform:

- **Primary storage — Railway Bucket** (S3-compatible). All committed events live here as parquet, manifests, and snapshots. Both query and ingest read and write to the same Bucket.
- **Query staging volume** mounted at `/data/staging` on the query node. Used for hot-tier query caches.
- **Ingest staging volume** mounted at `/data/staging` on the ingest node. Buffers in-flight events before they are flushed to the Bucket.

All three are provisioned automatically by the template.

### Implementation Details

After deployment, the two services have separate Railway-assigned URLs:

- **Query URL** — `https://parseable-query-xxxx.up.railway.app` — log in here for the UI and the SQL API
- **Ingest URL** — `https://parseable-ingest-xxxx.up.railway.app` — point log shippers here

Use the credentials configured during deployment (`P_USERNAME` and `P_PASSWORD`).

**Send a log event to the ingest node:**

```bash
curl -X POST "https://your-parseable-ingest.up.railway.app/api/v1/ingest" \
  -u "admin:your-password" \
  -H "Content-Type: application/json" \
  -H "X-P-Stream: teststream" \
  -d '[{"message": "Hello from Railway!", "level": "info"}]'
```

**Query logs from the query node:**

```bash
curl -X POST "https://your-parseable-query.up.railway.app/api/v1/query" \
  -u "admin:your-password" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT * FROM teststream",
    "startTime": "2024-01-01T00:00:00Z",
    "endTime": "2030-01-01T00:00:00Z"
  }'
```

Replace the URLs with your actual Railway URLs, and `admin:your-password` with the credentials you configured. The password is auto-generated and available in the **parseable-query** service variables.

### Service Variables

Both services run `parseable s3-store` from the same Dockerfile. They differ only in env vars.

**Shared variables (referenced into both services):**

| Variable          | Source                            |
| ----------------- | --------------------------------- |
| `P_S3_URL`        | `${{Bucket.ENDPOINT}}`            |
| `P_S3_ACCESS_KEY` | `${{Bucket.ACCESS_KEY_ID}}`       |
| `P_S3_SECRET_KEY` | `${{Bucket.SECRET_ACCESS_KEY}}`   |
| `P_S3_BUCKET`     | `${{Bucket.BUCKET}}`              |
| `P_S3_REGION`     | `${{Bucket.REGION}}`              |
| `P_ADDR`          | `0.0.0.0:8080`                    |
| `PORT`            | `8080`                            |
| `P_STAGING_DIR`   | `/data/staging`                   |

**Query service (`parseable-query`):**

| Variable     | Value                  |
| ------------ | ---------------------- |
| `P_MODE`     | `query`                |
| `P_USERNAME` | user input (`admin`)   |
| `P_PASSWORD` | user input or auto-gen |

**Ingest service (`parseable-ingest`):**

| Variable              | Value                                          |
| --------------------- | ---------------------------------------------- |
| `P_MODE`              | `ingest`                                       |
| `P_INGESTOR_ENDPOINT` | `${{RAILWAY_PRIVATE_DOMAIN}}:8080`             |
| `P_USERNAME`          | `${{parseable-query.P_USERNAME}}` (reference)  |
| `P_PASSWORD`          | `${{parseable-query.P_PASSWORD}}` (reference)  |

The query and ingest nodes must share identical credentials. Setting them as references from the ingest service to the query service guarantees they stay in sync.

## Scaling

The template provisions one query node and one ingestor. To add more ingestors after deployment:

1. In the Railway dashboard, duplicate the `parseable-ingest` service.
2. Keep all variables the same except update `P_INGESTOR_ENDPOINT` so it points at the new replica's private domain.
3. Each ingestor registers itself in the Bucket on startup; the query node picks them up automatically.

For autoscaled ingestion or large clusters, run Parseable on Kubernetes with the [Helm chart](https://github.com/parseablehq/helm-charts) instead.

## Further Reading

- [Standalone Parseable Railway template](https://railway.com/deploy/parseable-1) — single-node deployment
- [Parseable Cloud](https://app.parseable.com) — fully managed Parseable, no infrastructure to maintain
- [Parseable Documentation](https://www.parseable.com/docs) — configuration, API reference, and guides
- [Parseable GitHub](https://github.com/parseablehq/parseable) — source code and issue tracker
- [Parseable Docker Hub](https://hub.docker.com/r/parseable/parseable) — container images
- [Railway Documentation](https://docs.railway.com) — platform docs
- [Railway Buckets](https://docs.railway.com/reference/buckets) — S3-compatible storage on Railway
- [Deploy Distributed Parseable on Railway](https://www.parseable.com/docs/self-hosted/installation/distributed/railway) — step-by-step guide in Parseable developer docs
