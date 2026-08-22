#!/usr/bin/env bash
# Firewalld port exposure and /etc/hosts management.

HOSTKIT_HOSTS_MARKER="${HOSTKIT_HOSTS_MARKER:-hostkit-managed}"

hostkit_expose_help() {
  cat <<'EOF'
hostkit expose - LAN port and hosts exposure

Subcommands:
  port PORT [tcp|udp] [--remove]   Open/close firewalld port and print LAN URLs
  hosts --ip IP --host HOST...     Write managed /etc/hosts entries

Examples:
  hostkit expose port 8080
  hostkit expose port 443 tcp
  hostkit expose hosts --ip 192.168.1.5 --host app.staging --host admin.app.staging
EOF
}

hostkit_expose() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    port)
      hostkit_expose_port "$@"
      ;;
    hosts)
      hostkit_expose_hosts "$@"
      ;;
    ingress-ip|resolve-ingress-ip)
      hostkit_expose_resolve_ingress_ip "$@" || exit 1
      ;;
    -h|--help|help|"")
      hostkit_expose_help
      [[ -n "${sub}" ]] || exit 1
      ;;
    *)
      hostkit_error "Unknown expose subcommand: ${sub}"
      hostkit_expose_help
      exit 1
      ;;
  esac
}

hostkit_expose_port() {
  local port=""
  local proto="tcp"
  local remove=false

  for arg in "$@"; do
    case "$arg" in
      --remove|-r)
        remove=true
        ;;
      tcp|udp)
        proto="$arg"
        ;;
      -h|--help)
        cat <<'EOF'
hostkit expose port PORT [tcp|udp] [--remove]
EOF
        return 0
        ;;
      *)
        if [[ -z "$port" && "$arg" =~ ^[0-9]+$ ]]; then
          port="$arg"
        else
          hostkit_error "Unknown argument: $arg"
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$port" ]]; then
    hostkit_info "No port specified."
    hostkit_expose_help
    exit 0
  fi

  if (( port < 1 || port > 65535 )); then
    hostkit_error "Invalid port: ${port} (must be 1-65535)"
    exit 1
  fi

  hostkit_require_root
  hostkit_expose_configure_firewalld "${port}" "${proto}" "${remove}"
  hostkit_expose_check_listening "${port}" "${proto}"

  mapfile -t lan_ips < <(hostkit_expose_detect_lan_ips)

  echo ""
  if $remove; then
    hostkit_success "Port ${port}/${proto} is no longer exposed via firewalld."
    return 0
  fi

  echo "App exposure summary:"
  echo "   Port:     ${port}/${proto}"

  if ((${#lan_ips[@]} > 0)); then
    echo "   LAN IPs:"
    for ip in "${lan_ips[@]}"; do
      echo "     - ${ip}"
    done
    echo ""
    echo "   Access from Linux, Windows, or mobile (same Wi-Fi/LAN):"
    for ip in "${lan_ips[@]}"; do
      echo "     http://${ip}:${port}/"
    done
  else
    echo "   LAN IPs:  (none detected — check network connection)"
    echo ""
    echo "   Once connected, use: http://<host-lan-ip>:${port}/"
  fi

  echo ""
  echo "   No client-side setup required — plain IP/port works everywhere."
}

hostkit_expose_configure_firewalld() {
  local port="$1"
  local proto="$2"
  local remove="$3"

  if ! systemctl is-active --quiet firewalld 2>/dev/null; then
    hostkit_info "firewalld is not active; skipping firewall rules."
    return 0
  fi

  if [[ "${remove}" == "true" ]]; then
    hostkit_info "Closing ${port}/${proto} in firewalld..."
    firewall-cmd --permanent --remove-port="${port}/${proto}" || true
    firewall-cmd --reload || true
    hostkit_success "Port ${port}/${proto} closed in firewalld."
  else
    hostkit_info "Opening ${port}/${proto} in firewalld..."
    firewall-cmd --permanent --add-port="${port}/${proto}" || true
    firewall-cmd --reload || true
    hostkit_success "Port ${port}/${proto} opened in firewalld."
  fi
}

hostkit_expose_is_virtual_interface() {
  local iface="$1"
  case "$iface" in
    docker0|cni0|virbr*|flannel*|veth*)
      return 0
      ;;
  esac
  return 1
}

hostkit_expose_detect_lan_ips() {
  local _ iface _addr addr
  while read -r _ iface _ addr _; do
    addr="${addr%%/*}"
    if hostkit_expose_is_virtual_interface "$iface"; then
      continue
    fi
    echo "$addr"
  done < <(ip -4 -o addr show scope global 2>/dev/null)
}

hostkit_expose_check_listening() {
  local port="$1"
  local proto="$2"
  local ss_args=(-H -ln)

  if [[ "$proto" == "tcp" ]]; then
    ss_args=(-H -tln)
  else
    ss_args=(-H -uln)
  fi

  local listeners
  listeners="$(ss "${ss_args[@]}" "sport = :${port}" 2>/dev/null || true)"

  if [[ -z "$listeners" ]]; then
    hostkit_warn "Nothing is listening on ${port}/${proto} yet."
    hostkit_info "Start your app first, then verify from another device."
    return 0
  fi

  if [[ "$proto" == "tcp" ]]; then
    if echo "$listeners" | grep -q '127.0.0.1:' && ! echo "$listeners" | grep -Eq '(\*|0\.0\.0\.0|\[::\]):'; then
      hostkit_warn "Port ${port} is bound to 127.0.0.1 only."
      hostkit_info "Configure the app to listen on 0.0.0.0 for LAN access."
    fi
  fi
}

hostkit_expose_hosts() {
  local ip=""
  local hosts_file="/etc/hosts"
  local marker="${HOSTKIT_HOSTS_MARKER}"
  local -a hosts=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ip)
        ip="${2:-}"
        shift 2
        ;;
      --host)
        hosts+=("${2:-}")
        shift 2
        ;;
      --file)
        hosts_file="${2:-}"
        shift 2
        ;;
      --marker)
        marker="${2:-}"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
hostkit expose hosts --ip IP --host HOST... [--file /etc/hosts]
EOF
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [[ -z "${ip}" || ${#hosts[@]} -eq 0 ]]; then
    hostkit_error "--ip and at least one --host are required."
    exit 1
  fi

  hostkit_require_root

  local begin="# BEGIN ${marker}"
  local end="# END ${marker}"
  local tmp
  tmp="$(mktemp)"

  if [[ -f "${hosts_file}" ]]; then
    awk -v begin="${begin}" -v end="${end}" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      skip==0 { print }
    ' "${hosts_file}" > "${tmp}"
  else
    : > "${tmp}"
  fi

  {
    cat "${tmp}"
    echo "${begin}"
    for domain in "${hosts[@]}"; do
      echo "${ip} ${domain}"
    done
    echo "${end}"
  } > "${tmp}.new"

  install -m 644 "${tmp}.new" "${hosts_file}"
  rm -f "${tmp}" "${tmp}.new"

  hostkit_success "Updated ${hosts_file} for ${#hosts[@]} hostname(s) -> ${ip}"
  grep -F "${marker}" -A "$(( ${#hosts[@]} + 1 ))" "${hosts_file}" || true
}

hostkit_expose_resolve_ingress_ip() {
  local kubeconfig="${KUBECONFIG:-}"
  local kubectl_cmd=(kubectl)
  [[ -n "${kubeconfig}" ]] && kubectl_cmd=(kubectl --kubeconfig="${kubeconfig}")

  local ip=""
  ip="$("${kubectl_cmd[@]}" get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return 0
  fi

  ip="$("${kubectl_cmd[@]}" get ingress -A \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return 0
  fi

  return 1
}
