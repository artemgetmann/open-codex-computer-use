#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="${OPEN_COMPUTER_USE_E2E_CLI:-${repo_root}/.build/debug/OpenComputerUse}"
timeout_seconds="${OPEN_COMPUTER_USE_E2E_TIMEOUT_SECONDS:-3}"
disable_app_agent_proxy="${OPEN_COMPUTER_USE_E2E_DISABLE_APP_AGENT_PROXY:-1}"
monotonic_clock_command="${OPEN_COMPUTER_USE_E2E_MONOTONIC_MILLISECONDS_COMMAND:-}"

cd "${repo_root}"

if [[ -z "${OPEN_COMPUTER_USE_E2E_CLI:-}" ]]; then
  swift build --product OpenComputerUse
fi

if [[ ! -x "${cli}" ]]; then
  if command -v open-computer-use >/dev/null 2>&1; then
    cli="$(command -v open-computer-use)"
  else
    echo "Missing executable: ${cli}" >&2
    echo "Run swift build first, or set OPEN_COMPUTER_USE_E2E_CLI=/path/to/open-computer-use." >&2
    exit 1
  fi
fi

if [[ ! "${timeout_seconds}" =~ ^[1-9][0-9]*$ ]]; then
  echo "OPEN_COMPUTER_USE_E2E_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

monotonic_milliseconds() {
  local value=""

  # Tests may inject a deterministic monotonic clock to cover boundary
  # crossings without sleeping. Production verification uses macOS's bundled
  # Perl and its monotonic clock, so wall-clock changes and Bash's whole-second
  # SECONDS rounding cannot shorten the timeout window.
  if [[ -n "${monotonic_clock_command}" ]]; then
    value="$("${monotonic_clock_command}")"
  else
    value="$(/usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e \
      'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  fi

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "Monotonic clock returned an invalid millisecond value: ${value}" >&2
    return 1
  fi
  printf '%s\n' "${value}"
}

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-permission-e2e.XXXXXX")"
app_agent_owner_token="permission-e2e-$(uuidgen)"
pid=""
cleanup() {
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi

  # The token is attached only if this E2E invocation launched the app-agent.
  # A pre-existing release or Dev agent rejects the cleanup request.
  OPEN_COMPUTER_USE_APP_AGENT_OWNER_TOKEN="${app_agent_owner_token}" \
    "${cli}" __open-computer-use-stop-owned-app-agent >/dev/null 2>&1 || true
  rm -rf "${tmpdir}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Using CLI: ${cli}"
if [[ "${disable_app_agent_proxy}" == "1" || "${disable_app_agent_proxy}" == "true" || "${disable_app_agent_proxy}" == "yes" ]]; then
  echo "Using direct CLI permission checks (app-agent proxy disabled for this E2E)."
  run_cli() {
    OPEN_COMPUTER_USE_APP_AGENT_OWNER_TOKEN="${app_agent_owner_token}" \
      OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY=1 \
      "${cli}" "$@"
  }
else
  echo "Using default CLI app-agent proxy behavior."
  run_cli() {
    OPEN_COMPUTER_USE_APP_AGENT_OWNER_TOKEN="${app_agent_owner_token}" \
      "${cli}" "$@"
  }
fi

doctor_output="$(run_cli doctor)"
echo "${doctor_output}"

if [[ "${doctor_output}" != *"accessibility=granted"* ]] || [[ "${doctor_output}" != *"screenRecording=granted"* ]]; then
  echo "Expected doctor to report both permissions granted before running onboarding E2E." >&2
  exit 1
fi

stdout_file="${tmpdir}/onboarding.stdout"
stderr_file="${tmpdir}/onboarding.stderr"

run_cli >"${stdout_file}" 2>"${stderr_file}" &
pid="$!"

deadline_milliseconds=$(( $(monotonic_milliseconds) + timeout_seconds * 1000 ))
exit_code=""
while true; do
  now_milliseconds="$(monotonic_milliseconds)"
  if (( now_milliseconds >= deadline_milliseconds )); then
    break
  fi
  if ! kill -0 "${pid}" 2>/dev/null; then
    if wait "${pid}"; then
      exit_code=0
    else
      exit_code="$?"
    fi
    break
  fi
  sleep 0.05
done

if [[ -z "${exit_code}" ]]; then
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  echo "Permission onboarding did not exit within ${timeout_seconds}s even though doctor reported granted." >&2
  echo "--- stdout ---" >&2
  cat "${stdout_file}" >&2
  echo "--- stderr ---" >&2
  cat "${stderr_file}" >&2
  exit 1
fi

if [[ "${exit_code}" != "0" ]]; then
  echo "Permission onboarding command exited with ${exit_code}." >&2
  echo "--- stdout ---" >&2
  cat "${stdout_file}" >&2
  echo "--- stderr ---" >&2
  cat "${stderr_file}" >&2
  exit "${exit_code}"
fi

echo "Permission onboarding E2E passed: granted permissions do not leave onboarding running."
