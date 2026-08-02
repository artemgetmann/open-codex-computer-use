#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="${repo_root}/scripts/run-permission-onboarding-e2e.sh"
fake_cli="${repo_root}/scripts/test-fixtures/fake-permission-e2e-cli.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-cleanup-test.XXXXXX")"

cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

run_case() {
  local mode="$1"
  local expected_status="$2"
  local marker="${tmpdir}/${mode}.marker"
  local status=0

  OPEN_COMPUTER_USE_E2E_CLI="${fake_cli}" \
    OPEN_COMPUTER_USE_E2E_TIMEOUT_SECONDS=1 \
    OPEN_COMPUTER_USE_FAKE_E2E_MARKER="${marker}" \
    OPEN_COMPUTER_USE_FAKE_E2E_MODE="${mode}" \
    "${runner}" >/dev/null 2>&1 || status=$?

  if [[ "${status}" != "${expected_status}" ]]; then
    echo "Expected ${mode} status ${expected_status}, got ${status}." >&2
    exit 1
  fi
  if ! rg -q '^cleanup:permission-e2e-.+' "${marker}"; then
    echo "Expected owned app-agent cleanup for ${mode}." >&2
    exit 1
  fi
}

run_signal_case() {
  local marker="${tmpdir}/signal.marker"

  OPEN_COMPUTER_USE_E2E_CLI="${fake_cli}" \
    OPEN_COMPUTER_USE_E2E_TIMEOUT_SECONDS=30 \
    OPEN_COMPUTER_USE_FAKE_E2E_MARKER="${marker}" \
    OPEN_COMPUTER_USE_FAKE_E2E_MODE=hang \
    "${runner}" >/dev/null 2>&1 &
  local runner_pid="$!"

  local deadline=$((SECONDS + 5))
  while [[ ! -f "${marker}" ]] || ! rg -q '^started$' "${marker}"; do
    if (( SECONDS >= deadline )); then
      kill "${runner_pid}" 2>/dev/null || true
      wait "${runner_pid}" 2>/dev/null || true
      echo "Timed out waiting for signal test to start." >&2
      exit 1
    fi
    sleep 0.05
  done

  kill -TERM "${runner_pid}"
  local status=0
  wait "${runner_pid}" || status=$?

  if [[ "${status}" != "143" ]]; then
    echo "Expected signal status 143, got ${status}." >&2
    exit 1
  fi
  if ! rg -q '^cleanup:permission-e2e-.+' "${marker}"; then
    echo "Expected owned app-agent cleanup after TERM." >&2
    exit 1
  fi
}

run_first_poll_rollover_case() {
  local marker="${tmpdir}/rollover.marker"
  local clock_state="${tmpdir}/rollover-clock.state"
  local fake_clock="${tmpdir}/fake-monotonic-clock.sh"
  local status=0

  # Start at 1.999s and make the first poll happen at 2.001s. A whole-second
  # deadline would falsely expire at that boundary; the precise monotonic
  # deadline remains 2.999s and must accept the already-finished command.
  cat >"${fake_clock}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${OPEN_COMPUTER_USE_FAKE_CLOCK_STATE:?}"
calls=0
if [[ -f "${state}" ]]; then
  calls="$(cat "${state}")"
fi
if [[ "${calls}" -eq 0 ]]; then
  printf '1999\n'
else
  printf '2001\n'
fi
printf '%s\n' "$((calls + 1))" >"${state}"
EOF
  chmod +x "${fake_clock}"

  OPEN_COMPUTER_USE_E2E_CLI="${fake_cli}" \
    OPEN_COMPUTER_USE_E2E_TIMEOUT_SECONDS=1 \
    OPEN_COMPUTER_USE_E2E_MONOTONIC_MILLISECONDS_COMMAND="${fake_clock}" \
    OPEN_COMPUTER_USE_FAKE_CLOCK_STATE="${clock_state}" \
    OPEN_COMPUTER_USE_FAKE_E2E_MARKER="${marker}" \
    OPEN_COMPUTER_USE_FAKE_E2E_MODE=success \
    "${runner}" >/dev/null 2>&1 || status=$?

  if [[ "${status}" != "0" ]]; then
    echo "Expected first-poll rollover status 0, got ${status}." >&2
    exit 1
  fi
  if [[ ! -f "${clock_state}" ]] || (( $(cat "${clock_state}") < 2 )); then
    echo "Expected the precise monotonic clock on the first poll." >&2
    exit 1
  fi
  if ! rg -q '^cleanup:permission-e2e-.+' "${marker}"; then
    echo "Expected owned app-agent cleanup after first-poll rollover." >&2
    exit 1
  fi
}

run_first_poll_rollover_case
run_case success 0
run_case failure 7
run_case hang 1
run_signal_case

echo "Permission onboarding E2E cleanup tests passed."
