#!/usr/bin/env bash
# Start the Twingate connector for the nusx network (nusx-office-mac-01).
# Tokens are pulled from GCP Secret Manager at run time; requires docker and an authenticated gcloud.
set -euo pipefail

PROJECT=nusx-enterprise
CONNECTOR=nusx-office-mac-01

# Never sleep while on AC power, so the connector stays reachable.
sudo pmset -c sleep 0
AC_SLEEP=$(pmset -g custom | awk '/^AC Power:/{ac=1; next} /^[^ ]/{ac=0} ac && $1=="sleep"{print $2}')
if [[ "$AC_SLEEP" != "0" ]]; then
  echo "pmset: AC sleep is '${AC_SLEEP:-unset}', expected 0" >&2
  exit 1
fi
echo "pmset: AC sleep disabled"

# Leave a running connector alone; clear out a stopped one so the name is free.
if [[ "$(docker inspect -f '{{.State.Running}}' twingate-connector 2>/dev/null)" == "true" ]]; then
  echo "twingate-connector already running"
  exit 0
fi
docker rm twingate-connector >/dev/null 2>&1 || true

ACCESS=$(gcloud secrets versions access latest --secret="twingate-connector-${CONNECTOR}-access-token" --project="$PROJECT")
REFRESH=$(gcloud secrets versions access latest --secret="twingate-connector-${CONNECTOR}-refresh-token" --project="$PROJECT")

docker run -d --name twingate-connector --restart=unless-stopped \
  --add-host=host.docker.internal:host-gateway \
  -e TWINGATE_NETWORK=nusx \
  -e TWINGATE_ACCESS_TOKEN="$ACCESS" \
  -e TWINGATE_REFRESH_TOKEN="$REFRESH" \
  twingate/connector:1.93.0
