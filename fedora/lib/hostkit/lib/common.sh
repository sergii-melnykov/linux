#!/usr/bin/env bash
# Shared helpers for hostkit (sourced, not executed directly).

HOSTKIT_LOG_PREFIX="${HOSTKIT_LOG_PREFIX:-hostkit}"

hostkit_info() {
  echo "ℹ️  ${HOSTKIT_LOG_PREFIX}: $*"
}

hostkit_success() {
  echo "✅ ${HOSTKIT_LOG_PREFIX}: $*"
}

hostkit_warn() {
  echo "⚠️  ${HOSTKIT_LOG_PREFIX}: $*" >&2
}

hostkit_error() {
  echo "❌ ${HOSTKIT_LOG_PREFIX}: $*" >&2
}

hostkit_require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    hostkit_error "This command must be run as root (sudo)."
    exit 1
  fi
}

hostkit_require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    hostkit_error "${cmd} is not installed.${hint:+ ${hint}}"
    exit 1
  fi
}

# wait_for CMD [timeout_seconds] [interval_seconds]
hostkit_wait_for() {
  local desc="$1"
  local timeout="${2:-60}"
  local interval="${3:-1}"
  local i

  for ((i = 1; i <= timeout; i += interval)); do
    if eval "${desc}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${interval}"
  done
  return 1
}

hostkit_show_help() {
  cat <<'EOF'
hostkit - agnostic host infrastructure for Kubernetes ingress, TLS, and exposure

Usage:
  hostkit cluster up [options]
  hostkit cluster reset [options]
  hostkit cert local [options]
  hostkit cert ingress-default --secret NS/NAME [options]
  hostkit cert acme [options]
  hostkit cert renew
  hostkit expose port PORT [tcp|udp] [--remove]
  hostkit expose hosts --ip IP --host HOST... [options]
  hostkit tunnel install [options]

Run `hostkit help <command>` for details.
EOF
}
