#!/usr/bin/env bash
# Stop OFBiz and clean local dev session artifacts. Run once from repo root.
set -u

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
readonly SHUTDOWN_WAIT_SEC=60
readonly CLEAN_TIMEOUT_SEC=600

STOP_ONLY=false
GIT_RESTORE=true

usage() {
  echo "Usage: $(basename "$0") [--stop-only] [--no-git-restore]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop-only) STOP_ONLY=true ;;
    --no-git-restore) GIT_RESTORE=false ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

fail() {
  local code="$1"
  shift
  echo ""
  echo "=== OFBiz shutdown-and-clean FAILED (exit ${code}) ==="
  echo "$*"
  echo ""
  echo "Do not retry automatically. Fix the issue above, then re-run:"
  echo "  .cursor/skills/ofbiz-local-teardown/scripts/shutdown-and-clean.sh"
  exit "${code}"
}

log() { echo "[ofbiz-teardown] $*"; }

cd "${REPO_ROOT}" || fail 1 "Cannot cd to repo root: ${REPO_ROOT}"

if [[ ! -f "${REPO_ROOT}/gradlew" || ! -f "${REPO_ROOT}/build.gradle" ]]; then
  fail 1 "Not in OFBiz repo root (missing gradlew or build.gradle)."
fi

if [[ -f "${REPO_ROOT}/.java-env" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.java-env"
else
  log "WARN: .java-env not found; using current JAVA_HOME/PATH."
fi

gradlew() {
  "${REPO_ROOT}/gradlew" "$@"
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}" "${REPO_ROOT}/gradlew" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}" "${REPO_ROOT}/gradlew" "$@"
  else
    log "WARN: no timeout command; running without wall-clock limit."
    "${REPO_ROOT}/gradlew" "$@"
  fi
}

server_status() {
  gradlew "ofbiz --status" 2>/dev/null | grep 'Current Status' | tail -1 | sed 's/^Current Status : //'
}

is_running() {
  local status
  status="$(server_status 2>/dev/null || true)"
  [[ "${status}" == "Running" ]]
}

wait_for_stopped() {
  local wait_sec="${1:-60}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${wait_sec}" ]]; do
    if ! is_running; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

# --- 1. Stop OFBiz ---
if is_running; then
  log "Requesting graceful shutdown..."
  gradlew "ofbiz --shutdown" >/dev/null 2>&1 || true
  if wait_for_stopped "${SHUTDOWN_WAIT_SEC}"; then
    log "Server stopped gracefully."
  else
    log "Graceful shutdown timed out; force-terminating once..."
    gradlew terminateOfbiz >/dev/null 2>&1 || true
    sleep 5
    if is_running; then
      fail 2 "Server still Running after shutdown and terminateOfbiz. Check: lsof -i :8443"
    fi
    log "Server force-stopped."
  fi
else
  log "Server not running."
fi

if [[ "${STOP_ONLY}" == true ]]; then
  echo ""
  echo "=== OFBiz stop-only complete ==="
  echo "  Server:   stopped (or was not running)"
  echo "  Runtime:  unchanged (--stop-only)"
  echo "  Git:      unchanged (--stop-only)"
  exit 0
fi

# --- 2. Clean runtime artifacts ---
log "Running cleanAll (timeout ${CLEAN_TIMEOUT_SEC}s)..."
if ! run_with_timeout "${CLEAN_TIMEOUT_SEC}" cleanAll; then
  fail 3 "cleanAll failed or timed out after ${CLEAN_TIMEOUT_SEC}s."
fi
log "Runtime artifacts cleaned (demo DB, logs, build output, etc.)."

# --- 3. Restore tracked git changes ---
restored_summary="none"
if [[ "${GIT_RESTORE}" == true ]]; then
  if ! command -v git >/dev/null 2>&1; then
    log "WARN: git not found; skipping tracked file restore."
    restored_summary="skipped (git not found)"
  elif ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "WARN: not a git repo; skipping tracked file restore."
    restored_summary="skipped (not a git repo)"
  else
    restored_summary="$(git -C "${REPO_ROOT}" diff --name-only HEAD 2>/dev/null | grep -v '^\.gitignore$' | tr '\n' ' ')"
    if [[ -n "${restored_summary// /}" ]]; then
      log "Restoring tracked file changes (excluding .gitignore)..."
      while IFS= read -r file; do
        [[ -z "${file}" || "${file}" == ".gitignore" ]] && continue
        git -C "${REPO_ROOT}" restore --worktree --staged -- "${file}" 2>/dev/null || \
          git -C "${REPO_ROOT}" checkout -- "${file}" 2>/dev/null || true
      done < <(git -C "${REPO_ROOT}" diff --name-only HEAD 2>/dev/null)
    else
      restored_summary="none"
      log "No tracked file changes to restore."
    fi
  fi
else
  log "Skipping git restore (--no-git-restore)."
  restored_summary="skipped (--no-git-restore)"
fi

echo ""
echo "=== OFBiz teardown complete ==="
echo "  Server:   stopped"
echo "  Runtime:  cleanAll finished (demo DB removed; re-run ensure-running to reload)"
echo "  Git:      ${restored_summary}"
echo "  Kept:     untracked files (.cursor/, scripts/, .envrc, .java-env)"
exit 0
