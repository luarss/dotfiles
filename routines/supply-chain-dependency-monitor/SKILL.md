---
name: supply-chain-dependency-monitor
description: Supply chain dependency monitor
schedule: 0 8 * * * (UTC cron)
---

Scan all dependencies across repositories in the nus-etp organisation for supply chain risks.

1. Check for known vulnerabilities in direct and transitive dependencies using available security data.
2. Flag any dependencies with recent suspicious activity: unusual commit patterns, ownership changes, or newly-published versions with unexpected changes.
3. Identify pinned or outdated dependencies that are significantly behind the latest stable release.
4. Compile findings into a summary and post to the #luarss-security Slack channel.

Organize by severity (Critical, High, Medium). Include the affected repository, dependency name, version, and brief description of the risk. If no issues are found, post a brief all-clear message.
