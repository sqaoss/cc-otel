# cc-otel

A one-command, headless OTLP sink for [Claude Code](https://docs.claude.com/en/docs/claude-code) telemetry. It runs an
[OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) that fans out to
[VictoriaMetrics](https://victoriametrics.com/) (metrics) and [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
(logs), and accepts telemetry from any number of Claude Code sessions. MIT licensed.

**The repo is the runtime.** Clone it on any VPS, write your secrets into `.env`, run `./up.sh`. No build step, no
external state. Everything is reproducible from this repo.

## Quickstart

```bash
git clone https://github.com/sqaoss/cc-otel.git
cd cc-otel
cp .env.example .env && chmod 600 .env

# generate a strong ingest token and paste it into .env as INGEST_TOKEN
openssl rand -hex 32

# edit .env: pick INGEST_MODE, set INGEST_TOKEN (and DOMAIN/ACME_EMAIL for tls)
./up.sh
```

`up.sh` is idempotent — re-run it any time after editing `.env`. It installs Docker if missing (via
`get.docker.com`, tested on Ubuntu), creates data directories, and brings the stack up with `docker compose up -d`.

## Three modes

Set `INGEST_MODE` in `.env`:

| Mode | What it does | Exposure |
|------|--------------|----------|
| `private` | Token auth as defense-in-depth; bind the collector to a **private NIC IP** by setting `COLLECTOR_BIND` to that IP. | Private network only |
| `plain` | Token-only auth, collector exposed on the configured bind address. For trusted networks. | Wherever `COLLECTOR_BIND` points |
| `tls` | Caddy + Let's Encrypt terminate TLS on `$DOMAIN`. The collector is pinned to `127.0.0.1`; only Caddy is public. Public senders use `http/protobuf`. | `0.0.0.0:443` (Caddy) |

In `tls` mode you must set a real `DOMAIN` and `ACME_EMAIL`; `up.sh` will refuse the `otel.example.com` placeholder.

## Point a Claude Code session at it

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc          # tls mode: http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<receiver-ip>:4317   # tls: https://<domain>
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <token>"
export OTEL_LOG_USER_PROMPTS=1
export OTEL_LOG_TOOL_DETAILS=1
export OTEL_RESOURCE_ATTRIBUTES="service.name=claude-code,agent.name=<name>,host.name=<host>"
```

**Critical gotcha:** in `private`/`plain` mode the endpoint MUST be `http://`. Using `https://` makes Claude Code attempt
a TLS handshake against the plaintext receiver and silently fail. Only `tls` mode uses `https://`.

## How to query

**VictoriaLogs (LogsQL)** — fetch recent Claude Code log records:

```bash
curl -s "http://<receiver-ip>:9428/select/logsql/query" \
  --data-urlencode 'query=service.name:"claude-code"' \
  --data-urlencode 'limit=5'
```

**VictoriaMetrics (PromQL)** — list ingested metric names, then run an instant query:

```bash
# which claude_code.* metrics have arrived?
curl -s "http://<receiver-ip>:8428/api/v1/label/__name__/values" | tr ',' '\n' | grep claude_code

# instant query for a specific metric
curl -s "http://<receiver-ip>:8428/api/v1/query" --data-urlencode 'query=claude_code_token_usage_tokens_total'
```

Or just run the canned check:

```bash
./verify.sh <receiver-ip>
```

It probes both backends and prints `PASS`/`FAIL`, dumping recent collector logs and troubleshooting hints on failure.

## Retention

- `VM_RETENTION` — VictoriaMetrics retention in **months** (e.g. `3`).
- `VL_RETENTION` — VictoriaLogs retention as a **duration** (e.g. `90d`).

## Sizing

Sized for a small (~4 GB) box: the collector runs `memory_limiter` first at 1500 MiB limit / 512 MiB spike, so it sheds
load before the host is starved.

## License

[MIT](LICENSE) © 2026 cc-otel contributors
