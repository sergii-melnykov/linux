#!/usr/bin/env bash
# Cloudflare Tunnel installation helpers.

HOSTKIT_CLOUDFLARED_CONFIG="${HOSTKIT_CLOUDFLARED_CONFIG:-/etc/cloudflared/config.yml}"

hostkit_tunnel_help() {
  cat <<'EOF'
hostkit tunnel - outbound tunnel to expose local HTTPS services

Subcommands:
  install   Install/configure cloudflared systemd service

Examples:
  hostkit tunnel install --token YOUR_TUNNEL_TOKEN
  hostkit tunnel install --name my-tunnel --hostname staging.example.com
EOF
}

hostkit_tunnel() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    install)
      hostkit_tunnel_install "$@"
      ;;
    -h|--help|help|"")
      hostkit_tunnel_help
      [[ -n "${sub}" ]] || exit 1
      ;;
    *)
      hostkit_error "Unknown tunnel subcommand: ${sub}"
      hostkit_tunnel_help
      exit 1
      ;;
  esac
}

hostkit_tunnel_install_help() {
  cat <<'EOF'
hostkit tunnel install - configure cloudflared as a systemd service

Token mode (recommended — remotely managed tunnel):
  hostkit tunnel install --token TOKEN

Config mode (local config file):
  hostkit tunnel install --name TUNNEL_NAME --hostname HOST... [options]

Options:
  --token TOKEN            Cloudflare tunnel token (cloudflared service install)
  --name NAME              Named tunnel (config mode)
  --hostname HOST          Public hostname (repeatable, config mode)
  --credentials-file PATH  Path to tunnel credentials JSON (config mode)
  --origin URL             Origin service URL (default: https://127.0.0.1:443)
  --config PATH            Config output path (default: /etc/cloudflared/config.yml)
  -h, --help
EOF
}

hostkit_tunnel_install() {
  local token=""
  local name=""
  local origin="https://127.0.0.1:443"
  local config_path="${HOSTKIT_CLOUDFLARED_CONFIG}"
  local credentials_file=""
  local -a hostnames=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token)
        token="${2:-}"
        shift 2
        ;;
      --name)
        name="${2:-}"
        shift 2
        ;;
      --hostname)
        hostnames+=("${2:-}")
        shift 2
        ;;
      --origin)
        origin="${2:-}"
        shift 2
        ;;
      --credentials-file)
        credentials_file="${2:-}"
        shift 2
        ;;
      --config)
        config_path="${2:-}"
        shift 2
        ;;
      -h|--help)
        hostkit_tunnel_install_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_tunnel_install_help
        exit 1
        ;;
    esac
  done

  hostkit_require_root
  hostkit_require_cmd cloudflared "Install via: sudo bash linux/fedora/scripts/setup/31_cloudflared.sh"

  if [[ -n "${token}" ]]; then
    hostkit_info "Installing cloudflared service (token mode)..."
    cloudflared service install "${token}"
    systemctl enable --now cloudflared
    hostkit_success "cloudflared service installed and started."
    return 0
  fi

  if [[ -z "${name}" || ${#hostnames[@]} -eq 0 ]]; then
    hostkit_error "Either --token or (--name and --hostname) is required."
    hostkit_tunnel_install_help
    exit 1
  fi

  if [[ -z "${credentials_file}" ]]; then
    hostkit_error "--credentials-file is required in config mode."
    hostkit_info "Create a tunnel first: cloudflared tunnel login && cloudflared tunnel create ${name}"
    exit 1
  fi

  mkdir -p "$(dirname "${config_path}")"
  hostkit_info "Writing ${config_path}..."
  {
    echo "tunnel: ${name}"
    echo "credentials-file: ${credentials_file}"
    echo ""
    echo "ingress:"
    local host
    for host in "${hostnames[@]}"; do
      cat <<EOF
  - hostname: ${host}
    service: ${origin}
    originRequest:
      noTLSVerify: true
EOF
    done
    echo "  - service: http_status:404"
  } > "${config_path}"

  chmod 600 "${config_path}"
  cloudflared service install
  systemctl enable --now cloudflared
  hostkit_success "cloudflared configured (${#hostnames[@]} hostname(s) -> ${origin})."
  hostkit_warn "Cloudflare free tier limits request bodies (~100 MB); large uploads may fail."
}
