#!/usr/bin/env bash
set -euo pipefail

# Idempotent single-command bring-up for the cc-otel OTLP receiver stack.
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
	echo "ERROR: .env not found. Run: cp .env.example .env && chmod 600 .env" >&2
	exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${INGEST_TOKEN:=}"
if [[ -z "$INGEST_TOKEN" || "$INGEST_TOKEN" == "REPLACE_WITH_LONG_RANDOM_TOKEN" ]]; then
	echo "ERROR: INGEST_TOKEN is empty or still the placeholder." >&2
	echo "Generate one with: openssl rand -hex 32" >&2
	exit 1
fi

: "${INGEST_MODE:=private}"
: "${DOMAIN:=}"

case "$INGEST_MODE" in
	private | plain)
		COMPOSE_PROFILES=""
		COLLECTOR_BIND="${COLLECTOR_BIND:-0.0.0.0}"
		;;
	tls)
		if [[ -z "$DOMAIN" || "$DOMAIN" == "otel.example.com" ]]; then
			echo "ERROR: tls mode requires a real DOMAIN in .env (not otel.example.com)." >&2
			exit 1
		fi
		COMPOSE_PROFILES="tls"
		COLLECTOR_BIND="127.0.0.1"
		;;
	*)
		echo "ERROR: INGEST_MODE must be one of: private, plain, tls (got '$INGEST_MODE')." >&2
		exit 1
		;;
esac
export COMPOSE_PROFILES COLLECTOR_BIND

if ! command -v docker >/dev/null 2>&1; then
	echo "docker not found — installing via get.docker.com ..."
	curl -fsSL https://get.docker.com | sh
fi

mkdir -p data/victoriametrics data/victorialogs
if [[ "$INGEST_MODE" == "tls" ]]; then
	mkdir -p caddy/data caddy/config
fi

docker compose up -d

echo
echo "===================================================================="
echo " cc-otel is up (mode: ${INGEST_MODE})"
echo "===================================================================="
echo
echo "Point a Claude Code session at this receiver:"
echo
echo "  export CLAUDE_CODE_ENABLE_TELEMETRY=1"
echo "  export OTEL_METRICS_EXPORTER=otlp"
echo "  export OTEL_LOGS_EXPORTER=otlp"
if [[ "$INGEST_MODE" == "tls" ]]; then
	echo "  export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
	echo "  export OTEL_EXPORTER_OTLP_ENDPOINT=https://${DOMAIN}"
else
	echo "  export OTEL_EXPORTER_OTLP_PROTOCOL=grpc"
	echo "  export OTEL_EXPORTER_OTLP_ENDPOINT=http://${COLLECTOR_BIND}:${OTLP_GRPC_PORT:-4317}"
fi
echo "  export OTEL_EXPORTER_OTLP_HEADERS=\"Authorization=Bearer \${INGEST_TOKEN}\""
echo "  export OTEL_LOG_USER_PROMPTS=1"
echo "  export OTEL_LOG_TOOL_DETAILS=1"
echo "  export OTEL_RESOURCE_ATTRIBUTES=\"service.name=claude-code,agent.name=<name>,host.name=<host>\""
echo
if [[ "$INGEST_MODE" != "tls" ]]; then
	echo "  NOTE: in private/plain mode the endpoint MUST be http:// (not https://)."
	echo
fi
echo "Query URLs:"
echo "  VictoriaLogs (LogsQL):   http://${COLLECTOR_BIND}:9428/select/logsql/query"
echo "  VictoriaMetrics (PromQL): http://${COLLECTOR_BIND}:8428/api/v1/query"
echo "  Metric names:            http://${COLLECTOR_BIND}:8428/api/v1/label/__name__/values"
echo
echo "Sanity check:  ./verify.sh ${COLLECTOR_BIND}"
