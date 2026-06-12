---
name: gcp-infra-monitoring-pebbleroad
description: Review ETP infra costs (etp-intelligence-hub / etp-tfstate)
---

Please run the infra cost monitoring script in ~/work/etp-infra and send a briefing to "luarss-infra-briefing", a private slack channel

- before running anything, check GCP auth by running `gcloud auth application-default print-access-token > /dev/null 2>&1`; if it fails (exit code non-zero), stop and ask the user to run `gcloud auth application-default login`, then wait for confirmation before continuing
- run `./monitor-costs.sh`
- If the script exits with setup instructions (billing export not yet flowing), send that status as the briefing instead
- then run /commit-push skill to log the metrics appended under metrics/cost_audit/