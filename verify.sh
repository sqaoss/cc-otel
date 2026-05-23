#!/usr/bin/env bash
set -uo pipefail

# Operator sanity check: confirm Claude Code telemetry is landing in VL + VM.
# Reports PASS/FAIL per check without aborting on the first failure.
cd "$(dirname "$0")" || exit 1

if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
fi

HOST="${1:-${COLLECTOR_BIND:-127.0.0.1}}"
fail=0

echo "Verifying cc-otel ingest at host: ${HOST}"
echo "--------------------------------------------------------------------"

# 1) VictoriaLogs — any Claude Code logs?
logs=$(curl -s "http://${HOST}:9428/select/logsql/query" \
	--data-urlencode 'query=service.name:"claude-code"' \
	--data-urlencode 'limit=5')
if echo "$logs" | grep -q 'claude_code' || [[ -n "${logs//[[:space:]]/}" ]]; then
	echo "PASS  VictoriaLogs returned Claude Code log records."
else
	echo "FAIL  VictoriaLogs returned no Claude Code logs."
	fail=1
fi

# 2) VictoriaMetrics — any claude_code metric names?
count=$(curl -s "http://${HOST}:8428/api/v1/label/__name__/values" | tr ',' '\n' | grep -c claude_code)
if [[ "$count" -gt 0 ]]; then
	echo "PASS  VictoriaMetrics has ${count} claude_code metric name(s)."
else
	echo "FAIL  VictoriaMetrics has no claude_code metric names."
	fail=1
fi

echo "--------------------------------------------------------------------"
if [[ "$fail" -eq 0 ]]; then
	echo "SUMMARY: PASS — telemetry is flowing."
else
	echo "SUMMARY: FAIL — one or more checks failed."
	echo
	echo "Recent collector logs:"
	docker logs cc-otel-collector --tail 50 2>&1 || true
	echo
	echo "Hints:"
	echo "  401 ⇒ token mismatch between sender and INGEST_TOKEN."
	echo "  TLS handshake error ⇒ sender endpoint must be http:// (gRPC insecure), not https://."
fi

exit "$fail"
