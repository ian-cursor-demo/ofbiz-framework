#!/usr/bin/env bash
# Ensures OFBiz local dev: prerequisites, demo data, server running.
# Run once from repo root. Exits non-zero on failure; no internal retry loops.
set -u

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
readonly DERBY_OFBIZ="${REPO_ROOT}/runtime/data/derby/ofbiz"
readonly WRAPPER_JAR="${REPO_ROOT}/gradle/wrapper/gradle-wrapper.jar"
readonly HEALTH_URL="https://localhost:8443/webtools"
readonly LOAD_TIMEOUT_SEC=1800
readonly HEALTH_TIMEOUT_SEC=300
readonly HEALTH_POLL_SEC=10

fail() {
  local code="$1"
  shift
  echo ""
  echo "=== OFBiz ensure-running FAILED (exit ${code}) ==="
  echo "$*"
  echo ""
  echo "Do not retry automatically. Fix the issue above, then re-run:"
  echo "  .cursor/skills/ofbiz-local-dev/scripts/ensure-running.sh"
  exit "${code}"
}

log() { echo "[ofbiz-dev] $*"; }

cd "${REPO_ROOT}" || fail 1 "Cannot cd to repo root: ${REPO_ROOT}"

# Project-local JDK 17 (.java-env from scripts/setup-java17.sh; not global shell config)
if [[ -f "${REPO_ROOT}/.java-env" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.java-env"
else
  fail 1 "Missing .java-env. Run: scripts/setup-java17.sh (project-local JDK 17, does not change global shell)."
fi

# --- 1. Repo root ---
if [[ ! -f "${REPO_ROOT}/gradlew" || ! -f "${REPO_ROOT}/build.gradle" ]]; then
  fail 1 "Not in OFBiz repo root (missing gradlew or build.gradle)."
fi

# --- 2. JDK (17 documented; 17+ allowed with warning) ---
if ! command -v java >/dev/null 2>&1; then
  fail 1 "java not found. Install JDK 17+ and set JAVA_HOME."
fi
JAVA_VERSION_STRING="$(java -version 2>&1 | awk -F '"' '/version/ {print $2; exit}')"
JAVA_MAJOR="${JAVA_VERSION_STRING%%.*}"
if [[ "${JAVA_VERSION_STRING}" == 1.* ]]; then
  JAVA_MAJOR="${JAVA_VERSION_STRING#1.}"
  JAVA_MAJOR="${JAVA_MAJOR%%.*}"
fi
if [[ -z "${JAVA_MAJOR}" || "${JAVA_MAJOR}" -lt 17 ]]; then
  fail 1 "JDK 17+ required. Current: $(java -version 2>&1 | head -1)"
fi
if [[ "${JAVA_MAJOR}" != 17 ]]; then
  log "WARN: OFBiz documents JDK 17; using JDK ${JAVA_MAJOR} (unsupported, experimental)."
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  log "WARN: JAVA_HOME is not set (may still work)."
fi

# --- 3. Gradle wrapper ---
if [[ ! -f "${WRAPPER_JAR}" ]]; then
  log "Gradle wrapper jar missing; initializing..."
  if [[ ! -x "${REPO_ROOT}/gradle/init-gradle-wrapper.sh" ]]; then
    fail 1 "Missing ${WRAPPER_JAR} and init script gradle/init-gradle-wrapper.sh"
  fi
  if ! "${REPO_ROOT}/gradle/init-gradle-wrapper.sh"; then
    fail 1 "init-gradle-wrapper.sh failed."
  fi
fi

gradlew() {
  "${REPO_ROOT}/gradlew" "$@"
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}" "$@"
  else
    log "WARN: no timeout command; running without wall-clock limit."
    "$@"
  fi
}

# --- 4. Demo data ---
has_demo_data() {
  [[ -d "${DERBY_OFBIZ}" ]] && [[ -n "$(ls -A "${DERBY_OFBIZ}" 2>/dev/null)" ]]
}

if has_demo_data; then
  log "Demo database present at runtime/data/derby/ofbiz"
else
  log "Demo data missing; running cleanAll loadAll (timeout ${LOAD_TIMEOUT_SEC}s)..."
  if ! run_with_timeout "${LOAD_TIMEOUT_SEC}" gradlew cleanAll loadAll; then
    fail 2 "cleanAll loadAll failed or timed out after ${LOAD_TIMEOUT_SEC}s."
  fi
  if ! has_demo_data; then
    fail 2 "loadAll finished but runtime/data/derby/ofbiz is still empty."
  fi
  log "Demo data loaded."
fi

# --- 5. Server status ---
server_status() {
  gradlew "ofbiz --status" 2>/dev/null | grep 'Current Status' | tail -1 | sed 's/^Current Status : //'
}

is_running() {
  [[ "$(server_status)" == "Running" ]]
}

wait_for_running() {
  local wait_sec="${1:-60}"
  local elapsed=0
  while [[ "${elapsed}" -lt "${wait_sec}" ]]; do
    if is_running; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

if is_running; then
  log "OFBiz already running"
else
  log "Starting OFBiz in background..."
  if ! gradlew ofbizBackground; then
    fail 3 "ofbizBackground failed."
  fi
  if ! wait_for_running 120; then
    log "Status after wait: $(gradlew "ofbiz --status" 2>/dev/null | grep 'Current Status' || echo 'unknown')"
    fail 3 "Server did not report Running within 120s after ofbizBackground."
  fi
  log "OFBiz started (Running)"
fi

# --- 6. HTTPS health ---
log "Waiting for ${HEALTH_URL} (up to ${HEALTH_TIMEOUT_SEC}s)..."
elapsed=0
while [[ "${elapsed}" -lt "${HEALTH_TIMEOUT_SEC}" ]]; do
  http_code=""
  if command -v curl >/dev/null 2>&1; then
    http_code="$(curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "${HEALTH_URL}" 2>/dev/null || true)"
  fi
  if [[ "${http_code}" =~ ^[23] ]]; then
    echo ""
    echo "=== OFBiz is ready ==="
    echo "  URL:      ${HEALTH_URL}"
    echo "  Login:    admin / ofbiz"
    echo "  Status:   $(server_status)"
    echo "  Logs:     runtime/logs/console.log"
    exit 0
  fi
  sleep "${HEALTH_POLL_SEC}"
  elapsed=$((elapsed + HEALTH_POLL_SEC))
  log "  ... waiting (${elapsed}s / ${HEALTH_TIMEOUT_SEC}s, last HTTP: ${http_code:-none})"
done

fail 4 "Health check timed out after ${HEALTH_TIMEOUT_SEC}s. Check runtime/logs/console.log"
