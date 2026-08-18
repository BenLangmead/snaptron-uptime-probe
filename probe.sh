#!/usr/bin/env bash
# Off-campus availability probe for https://snaptron.cs.jhu.edu/
#
# Runs on a GitHub-hosted runner, which sits in Azure IP space well outside the
# JHU network. Its purpose is to disagree with the incumbent monitor
# (uptime.bot): if that monitor reports the site down while this probe reaches
# it fine, the fault is specific to that monitor's source address rather than to
# the service.
#
# Every run records the runner's own egress IP, because the hypothesis under
# test is a per-source-IP block and the answer is meaningless without knowing
# which address was doing the asking.
#
# Timestamps are UTC (runners are UTC). The snaptron01 and devlangmead1
# collectors log local Eastern time; do not compare them without converting.

set -uo pipefail

TARGET_URL='https://snaptron.cs.jhu.edu/'
TARGET_HOST='snaptron.cs.jhu.edu'
TARGET_IP='128.220.122.37'
CONTROL_URL='https://www.jhu.edu/'

mkdir -p results
OUT="results/$(date -u +%F).tsv"
now() { date -u +%FT%TZ; }
log() { printf '%s\t%s\t%s\n' "$(now)" "$1" "${*:2}" >> "$OUT"; }

egress=$(curl -s --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
log egress "ip=${egress:-unknown} runner=${RUNNER_NAME:-unknown}"

probe() {
  local kind="$1" url="$2" res code tt tc ta sz
  res=$(curl -s -o /dev/null --max-time 25 \
        -w '%{http_code} %{time_total} %{time_connect} %{time_appconnect} %{size_download}' \
        "$url" 2>/dev/null)
  if [ -z "$res" ]; then
    log "$kind" "code=000 err=no_response"
    return 1
  fi
  read -r code tt tc ta sz <<<"$res"
  log "$kind" "code=$code total=$tt connect=$tc tls=$ta bytes=$sz"
  [ "$code" = "200" ]
}

if probe target "$TARGET_URL"; then
  exit 0
fi

# Failure path. Capture only things that need no extra packages, so the record
# is written before a slow apt install could time the job out.
log capture "reason=target_probe_failed"
probe control "$CONTROL_URL" || true

for port in 443 80; do
  if timeout 8 bash -c ">/dev/tcp/${TARGET_IP}/${port}" 2>/dev/null; then
    log tcp "port=$port state=open"
  else
    log tcp "port=$port state=unreachable"
  fi
done

resolved=$(getent hosts "$TARGET_HOST" 2>/dev/null | awk '{print $1}' | paste -sd, -)
log dns "resolved=${resolved:-none}"

detail="results/failure-$(date -u +%Y%m%dT%H%M%SZ).txt"
{
  echo "=== $(now) target probe failed ==="
  echo "egress ip: ${egress:-unknown}"
  echo "--- curl -v ---"
  curl -sv -o /dev/null --max-time 25 "$TARGET_URL" 2>&1 | tail -40
} > "$detail" 2>&1
log capture "file=$(basename "$detail")"

# Exit 0 so a genuine outage does not show as a red workflow run; the data is
# the deliverable, and a failed run would also skip the commit step.
exit 0
