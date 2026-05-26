---
name: ofbiz-local-dev
description: Ensures Apache OFBiz local dev prerequisites, demo data, and server are ready. Checks JDK, Gradle wrapper, Derby demo database, and HTTPS on 8443; loads or starts only when needed. Use when running OFBiz locally, starting dev servers, onboarding, or when the user asks how to run OFBiz.
---

# OFBiz Local Dev

Get OFBiz running locally with demo data. **Run the ensure script once** from the repo root; do not retry failed steps in a loop.

## Quick start

One-time project JDK setup (does **not** modify `~/.zshrc`):

```bash
scripts/setup-java17.sh
```

Then from the OFBiz repo root:

```bash
.cursor/skills/ofbiz-local-dev/scripts/ensure-running.sh
```

Manual `./gradlew` in this repo: `source .java-env` first, or use [direnv](https://direnv.net/) (`direnv allow` reads `.envrc`).

On success, open https://localhost:8443/webtools (login: **admin** / **ofbiz**).

Other URLs: `/ordermgr`, `/accounting`.

## Agent workflow

1. **Run the script once** from repo root (not from inside the skill directory).
2. **If exit 0** — report running URL and credentials; optionally verify with `./gradlew "ofbiz --status"`.
3. **If non-zero** — read the script's final error block, report the failure, and **stop**. Do not automatically re-run `loadAll`, `cleanAll`, or start commands unless the user asks after you explain the blocker.
4. **Do not churn**: no retry loops, no parallel duplicate starts, no repeated `cleanAll loadAll` on transient errors.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Server healthy at https://localhost:8443 |
| 1 | Prerequisites missing (JDK, wrapper, repo root) |
| 2 | Demo data load failed or timed out |
| 3 | Server failed to start |
| 4 | Server started but health check timed out |

## What the script checks (in order)

1. **Repo root** — `gradlew` and `build.gradle` present
2. **JDK** — requires 17+; warns if not exactly 17 (project documents JDK 17 only)
3. **Gradle wrapper** — runs `./gradle/init-gradle-wrapper.sh` if `gradle/wrapper/gradle-wrapper.jar` is missing
4. **Demo data** — `runtime/data/derby/ofbiz` exists and is non-empty; if not, runs `./gradlew cleanAll loadAll` (once, 30 min timeout)
5. **Server** — `./gradlew "ofbiz --status"`; if not running, `./gradlew ofbizBackground` (once)
6. **Health** — polls https://localhost:8443/webtools for up to 5 minutes

## Manual commands (when script is not enough)

| Goal | Command |
|------|---------|
| Force fresh demo data | `./gradlew cleanAll loadAll` |
| Start (foreground) | `./gradlew ofbiz` |
| Start (background) | `./gradlew ofbizBackground` |
| Status | `./gradlew "ofbiz --status"` |
| Stop | `./gradlew "ofbiz --shutdown"` |
| Force kill | `./gradlew terminateOfbiz` |
| Debug (port 5005) | `./gradlew ofbiz --debug-jvm` |
| **End session** | `ofbiz-local-teardown` → `.cursor/skills/ofbiz-local-teardown/scripts/shutdown-and-clean.sh` |

## Troubleshooting (report, don't loop)

- **loadAll timeout** — first run downloads dependencies; suggest user re-run manually with stable network. Do not auto-retry.
- **Port 8443 in use** — check `./gradlew "ofbiz --status"` or `lsof -i :8443`; stop conflicting process or use `--portoffset`.
- **Stale/partial DB** — if load fails with entity errors, user may need `./gradlew cleanAll loadAll` once (destructive).
- **macOS / Unix** — always use `./gradlew`, not `gradlew`.

## Requirements

- JDK 17+ (17 is documented/tested; newer versions are experimental)
- Run from repo root; avoid paths with spaces on Windows
