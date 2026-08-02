#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  doctor)
    echo "Permissions: accessibility=granted, screenRecording=granted"
    ;;
  __open-computer-use-stop-owned-app-agent)
    printf 'cleanup:%s\n' "${OPEN_COMPUTER_USE_APP_AGENT_OWNER_TOKEN:-missing}" >> "${OPEN_COMPUTER_USE_FAKE_E2E_MARKER:?}"
    ;;
  "")
    printf 'started\n' >> "${OPEN_COMPUTER_USE_FAKE_E2E_MARKER:?}"
    case "${OPEN_COMPUTER_USE_FAKE_E2E_MODE:-success}" in
      success)
        exit 0
        ;;
      failure)
        exit 7
        ;;
      hang)
        trap 'exit 0' TERM INT HUP
        while true; do
          sleep 0.1
        done
        ;;
      *)
        echo "Unsupported fake E2E mode: ${OPEN_COMPUTER_USE_FAKE_E2E_MODE}" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Unexpected fake E2E command: $*" >&2
    exit 2
    ;;
esac
