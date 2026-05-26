---
name: ofbiz-local-teardown
description: Stops Apache OFBiz local dev, removes runtime session artifacts (demo DB, logs, build output), and restores tracked git file changes. Use when shutting down OFBiz, ending a dev session, cleaning up local changes, or pairing with ofbiz-local-dev after finishing work.
---

# OFBiz Local Teardown

Stop OFBiz and reset the workspace to a clean state. **Run the script once** from repo root; do not retry failed steps in a loop.

## Quick start

From the OFBiz repo root:

```bash
.cursor/skills/ofbiz-local-teardown/scripts/shutdown-and-clean.sh
```

Options:

```bash
# Stop server only (keep runtime data and git changes)
.cursor/skills/ofbiz-local-teardown/scripts/shutdown-and-clean.sh --stop-only

# Skip reverting tracked git modifications
.cursor/skills/ofbiz-local-teardown/scripts/shutdown-and-clean.sh --no-git-restore
```

## Agent workflow

1. **Run the script once** from repo root.
2. **If exit 0** — confirm server stopped, summarize what was cleaned.
3. **If non-zero** — read the error block, report, and **stop**. Do not loop shutdown/cleanAll/restore.
4. **Do not churn**: no repeated `terminateOfbiz` or `cleanAll` without user approval.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Teardown complete (per selected mode) |
| 1 | Repo root / gradlew missing |
| 2 | Server still running after shutdown + terminate |
| 3 | `cleanAll` failed or timed out |

## What the default run does

1. **Stop OFBiz** — `ofbiz --shutdown`, wait up to 60s; then `terminateOfbiz` once if needed
2. **Clean runtime** — `./gradlew cleanAll` (Derby demo DB, logs, catalina work, indexes, uploads, build output, etc.)
3. **Restore git** — `git restore` tracked files modified during the session (does **not** delete untracked files; **`.gitignore` is never touched**)

### Preserved (not removed)

- Untracked project files: `.cursor/`, `scripts/`, `.envrc`, `.java-env`
- Committed history; only **tracked working-tree edits** are reverted

## Pairing with ofbiz-local-dev

| Start session | End session |
|---------------|-------------|
| `ofbiz-local-dev` → `ensure-running.sh` | `ofbiz-local-teardown` → `shutdown-and-clean.sh` |

Next session: run `ensure-running.sh` again (reloads demo data if DB was cleaned).

## Manual commands

| Goal | Command |
|------|---------|
| Graceful stop | `source .java-env && ./gradlew "ofbiz --shutdown"` |
| Force kill | `source .java-env && ./gradlew terminateOfbiz` |
| Runtime cleanup only | `source .java-env && ./gradlew cleanAll` |
| Restore tracked edits | `git restore --worktree --staged .` |

## Troubleshooting (report, don't loop)

- **Shutdown hangs** — script force-terminates once; if still running, report PID from `lsof -i :8443`.
- **cleanAll slow** — normal on first run after heavy dev; 10 min timeout then stop.
- **Intentional git changes kept** — use `--no-git-restore` or commit work before teardown.
