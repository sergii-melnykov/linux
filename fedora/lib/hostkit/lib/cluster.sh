#!/usr/bin/env bash
# k3s cluster bring-up: registry mirror, k3s service, ingress-nginx, metrics-server.

hostkit_cluster_node_name() {
  echo "${K3S_NODE_NAME:-k3s-home}"
}

hostkit_cluster_help() {
  cat <<'EOF'
hostkit cluster - k3s cluster lifecycle

Usage:
  hostkit cluster up [options]
  hostkit cluster reset [options]

Subcommands:
  up       Start/configure k3s with ingress-nginx and metrics-server
  reset    Destroy cluster state and optionally recreate (wipes local-path data)

Options (up):
  --registry HOST:PORT     Insecure registry mirror (default: localhost:5000)
  --ingress-nginx VERSION  ingress-nginx manifest tag (default: controller-v1.11.3)
  --kubeconfig PATH        k3s kubeconfig (default: /etc/rancher/k3s/k3s.yaml)
  --resolv-conf PATH       systemd-resolved resolv.conf for k3s (default: /run/systemd/resolve/resolv.conf)
  --node-name NAME         Stable k3s node name (default: k3s-home or K3S_NODE_NAME)
  --no-metrics-server      Skip metrics-server install
  -h, --help               Show this help

Options (reset):
  --up                     Run `hostkit cluster up` after wiping cluster data
  --force                  Skip confirmation prompt
  -h, --help               Show this help

Notes:
  k3s node name is pinned in /etc/rancher/k3s/config.yaml so local-path PVs survive OS hostname changes.
  If the cluster was created before node-name pinning or the node identity drifted, reset and redeploy:
    sudo hostkit cluster reset --up
    ./deploy-prod.sh
EOF
}

hostkit_cluster() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    up)
      hostkit_cluster_up "$@"
      ;;
    reset)
      hostkit_cluster_reset "$@"
      ;;
    -h|--help|help)
      hostkit_cluster_help
      ;;
    "")
      hostkit_cluster_help
      exit 1
      ;;
    *)
      hostkit_error "Unknown cluster subcommand: ${sub}"
      hostkit_cluster_help
      exit 1
      ;;
  esac
}

hostkit_cluster_up() {
  local registry="${APP_REGISTRY:-localhost:5000}"
  local ingress_version="${INGRESS_NGINX_VERSION:-controller-v1.11.3}"
  local kubeconfig="${K3S_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  local resolv_conf="${K3S_RESOLV_CONF:-/run/systemd/resolve/resolv.conf}"
  local node_name
  node_name="$(hostkit_cluster_node_name)"
  local install_metrics=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --registry)
        registry="${2:-}"
        shift 2
        ;;
      --ingress-nginx)
        ingress_version="${2:-}"
        shift 2
        ;;
      --kubeconfig)
        kubeconfig="${2:-}"
        shift 2
        ;;
      --resolv-conf)
        resolv_conf="${2:-}"
        shift 2
        ;;
      --node-name)
        K3S_NODE_NAME="${2:-}"
        node_name="$(hostkit_cluster_node_name)"
        shift 2
        ;;
      --no-metrics-server)
        install_metrics=false
        shift
        ;;
      -h|--help)
        hostkit_cluster_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_cluster_help
        exit 1
        ;;
    esac
  done

  hostkit_require_root
  hostkit_require_cmd curl

  local config_changed=false
  if hostkit_cluster_write_config_yaml "${resolv_conf}" "${node_name}"; then
    config_changed=true
  fi

  hostkit_cluster_write_registries_yaml "${registry}"
  hostkit_cluster_ensure_k3s "${resolv_conf}" "${node_name}" "${config_changed}"
  export KUBECONFIG="${kubeconfig}"
  hostkit_cluster_verify_node_name "${kubeconfig}" "${node_name}"
  hostkit_cluster_install_ingress_nginx "${ingress_version}" "${kubeconfig}"

  if [[ "${install_metrics}" == "true" ]]; then
    hostkit_cluster_install_metrics_server "${kubeconfig}"
  fi

  hostkit_success "Cluster is ready."
  hostkit_info "kubeconfig: ${kubeconfig}"
  hostkit_info "k3s node name: ${node_name}"
  hostkit_info "Registry mirror: ${registry}"
}

hostkit_cluster_reset() {
  local run_up=false
  local force=false
  local reply
  local up_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --up)
        run_up=true
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --registry|--ingress-nginx|--kubeconfig|--resolv-conf|--node-name)
        up_args+=("$1" "${2:-}")
        shift 2
        ;;
      --no-metrics-server)
        up_args+=("$1")
        shift
        ;;
      -h|--help)
        hostkit_cluster_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_cluster_help
        exit 1
        ;;
    esac
  done

  hostkit_require_root

  if [[ "${force}" != "true" ]]; then
    hostkit_warn "This permanently deletes the k3s cluster state, workloads, and local-path volumes."
    if [[ -t 0 ]]; then
      read -r -p "Continue? [y/N] " reply
      case "${reply}" in
        y|Y|yes|Yes) ;;
        *)
          hostkit_info "Reset cancelled."
          return 0
          ;;
      esac
    else
      hostkit_error "Non-interactive reset requires --force."
      exit 1
    fi
  fi

  hostkit_info "Stopping k3s and removing cluster data..."
  if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    /usr/local/bin/k3s-uninstall.sh
  else
    systemctl disable k3s >/dev/null 2>&1 || true
    systemctl stop k3s >/dev/null 2>&1 || true
    if [[ -x /usr/local/bin/k3s-killall.sh ]]; then
      /usr/local/bin/k3s-killall.sh
    fi
    rm -rf /var/lib/rancher/k3s
    rm -f /etc/systemd/system/k3s.service
    rm -f /etc/systemd/system/k3s.service.env
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  hostkit_success "k3s cluster data removed."

  if [[ "${run_up}" == "true" ]]; then
    hostkit_cluster_up "${up_args[@]}"
  else
    hostkit_info "Recreate the cluster with: sudo hostkit cluster up"
  fi
}

hostkit_cluster_write_config_yaml() {
  local resolv_conf="$1"
  local node_name="$2"
  local config_path="/etc/rancher/k3s/config.yaml"
  local tmp
  tmp="$(mktemp)"

  mkdir -p /etc/rancher/k3s
  cat > "${tmp}" <<EOF
node-name: ${node_name}
disable:
  - traefik
write-kubeconfig-mode: "0644"
resolv-conf: ${resolv_conf}
EOF

  if [[ -f "${config_path}" ]] && cmp -s "${tmp}" "${config_path}"; then
    rm -f "${tmp}"
    return 1
  fi

  cat "${tmp}" > "${config_path}"
  rm -f "${tmp}"
  hostkit_success "Wrote ${config_path} (node-name: ${node_name})"
  return 0
}

hostkit_cluster_write_registries_yaml() {
  local registry="$1"
  local registry_host="${registry%%/*}"

  hostkit_info "Configuring k3s insecure registry: ${registry_host}"
  mkdir -p /etc/rancher/k3s
  cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "${registry_host}":
    endpoint:
      - "http://${registry_host}"
configs:
  "${registry_host}":
    tls:
      insecure_skip_verify: true
EOF
  hostkit_success "Wrote /etc/rancher/k3s/registries.yaml"
}

hostkit_cluster_ensure_k3s() {
  local resolv_conf="$1"
  local node_name="$2"
  local config_changed="${3:-false}"
  local exec_args="server --node-name=${node_name} --disable=traefik --write-kubeconfig-mode=644 --resolv-conf=${resolv_conf}"

  if command -v k3s >/dev/null 2>&1; then
    hostkit_info "k3s binary already installed; skipping get.k3s.io."
  else
    hostkit_info "k3s not found; installing via get.k3s.io..."
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y container-selinux || true
    fi
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="${exec_args}" sh -
    hostkit_success "k3s installed."
  fi

  systemctl enable k3s >/dev/null 2>&1 || true

  if [[ "${config_changed}" == "true" ]] && systemctl is-active --quiet k3s 2>/dev/null; then
    hostkit_info "k3s config changed — restarting to apply node-name=${node_name}..."
    systemctl restart k3s
  elif systemctl is-active --quiet k3s 2>/dev/null; then
    hostkit_info "k3s service is already running."
  else
    hostkit_info "Enabling and starting k3s..."
    systemctl restart k3s
  fi

  local kubeconfig="/etc/rancher/k3s/k3s.yaml"
  hostkit_info "Waiting for k3s API server..."
  if ! hostkit_wait_for "[[ -r '${kubeconfig}' ]] && KUBECONFIG='${kubeconfig}' kubectl get --raw='/readyz'" 60 1; then
    hostkit_error "k3s did not become ready within 60s."
    hostkit_info "Check: journalctl -u k3s -e"
    exit 1
  fi
  hostkit_success "k3s is ready."
}

hostkit_cluster_verify_node_name() {
  local kubeconfig="$1"
  local expected_node="$2"
  local ready_nodes ready_count actual_node

  export KUBECONFIG="${kubeconfig}"
  hostkit_require_cmd kubectl

  ready_nodes="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {print $1}')"
  ready_count="$(wc -l <<< "${ready_nodes}" | tr -d ' ')"
  actual_node="$(awk 'NR == 1 {print; exit}' <<< "${ready_nodes}")"

  if [[ "${ready_count}" -gt 1 ]]; then
    hostkit_error "Multiple Ready nodes detected (${ready_nodes//$'\n'/, })."
    hostkit_info "Reset the cluster: sudo hostkit cluster reset --up"
    exit 1
  fi

  if [[ -n "${actual_node}" && "${actual_node}" != "${expected_node}" ]]; then
    hostkit_error "Ready node is '${actual_node}' but pinned node-name is '${expected_node}'."
    hostkit_info "Existing cluster state is incompatible. Reset and redeploy:"
    hostkit_info "  sudo hostkit cluster reset --up"
    hostkit_info "  ./deploy-prod.sh"
    exit 1
  fi

  hostkit_success "Node identity verified (${expected_node})."
}

hostkit_cluster_install_ingress_nginx() {
  local ingress_version="$1"
  local kubeconfig="$2"

  export KUBECONFIG="${kubeconfig}"
  hostkit_require_cmd kubectl

  if kubectl get ingressclass nginx >/dev/null 2>&1; then
    hostkit_success "ingress-nginx IngressClass 'nginx' already exists."
    return 0
  fi

  hostkit_info "Installing ingress-nginx (${ingress_version})..."
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${ingress_version}/deploy/static/provider/cloud/deploy.yaml"

  hostkit_info "Waiting for ingress-nginx controller pod..."
  local i
  for i in $(seq 1 60); do
    if [[ -n "$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o name 2>/dev/null)" ]]; then
      break
    fi
    if [[ "$i" -eq 60 ]]; then
      hostkit_error "ingress-nginx controller pod was not created within 120s."
      exit 1
    fi
    sleep 2
  done

  hostkit_info "Waiting for ingress-nginx controller to be ready..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
  hostkit_success "ingress-nginx is ready."
}

hostkit_cluster_install_metrics_server() {
  local kubeconfig="$1"
  export KUBECONFIG="${kubeconfig}"

  if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    hostkit_success "metrics-server already installed."
    return 0
  fi

  hostkit_info "Installing metrics-server..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl patch deployment metrics-server -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
    || hostkit_warn "metrics-server patch failed (non-fatal for single-node k3s)."
  hostkit_success "metrics-server installed."
}
