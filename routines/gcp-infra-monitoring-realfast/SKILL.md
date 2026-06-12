---
name: gcp-infra-monitoring-realfast
description: Review infra
---

Please run the infra monitoring script and report to "luarss-infra-briefings", a private slack channel

- before running anything, check GCP auth by running `gcloud auth application-default print-access-token > /dev/null 2>&1`; if it fails (exit code non-zero), stop and ask the user to run `gcloud auth application-default login`, then wait for confirmation before continuing
- `./scripts/bq_cost_audit.sh -p nus-enterprise -r asia-southeast1`
- then run /commit-push skill to log the metrics
- send the HTML in the update