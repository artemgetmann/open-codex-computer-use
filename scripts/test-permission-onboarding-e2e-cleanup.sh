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

run_case success 0
run_case failure 7
run_case hang 1
run_signal_case

echo "Permission onboarding E2E cleanup tests passed."
