#!/usr/bin/env bash
# Wire host-port docker-compose apps into ingress-nginx (reachable via Cloudflare Tunnel).

hostkit_expose_help() {
  cat <<'EOF'
hostkit expose - wire docker-compose apps into ingress-nginx

Subcommands:
  docker-app --name NAME --port PORT --host HOST...
                                              Wire a host-port docker-compose app into ingress-nginx
  ingress-ip                                  Print the ingress-nginx LoadBalancer IP (diagnostic)

Examples:
  hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com
  hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com --remove
EOF
}

hostkit_expose() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    docker-app)
      hostkit_expose_docker_app "$@"
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

hostkit_expose_docker_app_help() {
  cat <<'EOF'
hostkit expose docker-app - expose a docker-compose app via ingress-nginx

Creates a selector-less Service + Endpoints (pointing at host IP:port) and an Ingress
so the app is reachable through the same ingress-nginx / Cloudflare Tunnel as k8s apps.

Usage:
  hostkit expose docker-app --name NAME --port PORT --host HOSTNAME... [options]

Options:
  --name NAME              Kubernetes object name (Service/Endpoints/Ingress)
  --port PORT              Host port the docker-compose app listens on
  --host HOSTNAME          Public hostname for Ingress (repeatable)
  --namespace NS           Namespace (default: default)
  --service-port PORT      Service port exposed to Ingress (default: 80)
  --host-ip IP             Override host IP (default: auto-detect)
  --ingress-class NAME     IngressClass (default: nginx)
  --tls-secret NAME        Existing TLS secret name for Ingress tls block
  --kubeconfig PATH        Kubeconfig path (default: KUBECONFIG or /etc/rancher/k3s/k3s.yaml)
  --remove                 Delete Service/Endpoints/Ingress instead of applying
  -h, --help

Examples:
  hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com
  hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com \
    --tls-secret myapp-tls --namespace apps
EOF
}

hostkit_expose_detect_host_ip() {
  local ip
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
  if [[ -z "${ip}" ]]; then
    hostkit_error "Could not auto-detect host IP. Pass --host-ip explicitly."
    exit 1
  fi
  echo "${ip}"
}

hostkit_expose_docker_app_render_yaml() {
  local name="$1"
  local namespace="$2"
  local host_ip="$3"
  local port="$4"
  local service_port="$5"
  local ingress_class="$6"
  local tls_secret="$7"
  shift 7
  local -a hostnames=("$@")

  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: hostkit
    app.kubernetes.io/component: docker-app
spec:
  ports:
    - port: ${service_port}
      targetPort: ${port}
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: ${name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: hostkit
    app.kubernetes.io/component: docker-app
subsets:
  - addresses:
      - ip: ${host_ip}
    ports:
      - port: ${port}
        protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: hostkit
    app.kubernetes.io/component: docker-app
spec:
  ingressClassName: ${ingress_class}
EOF

  if [[ -n "${tls_secret}" ]]; then
    cat <<EOF
  tls:
    - secretName: ${tls_secret}
      hosts:
EOF
    local host
    for host in "${hostnames[@]}"; do
      echo "        - ${host}"
    done
  fi

  echo "  rules:"
  local host
  for host in "${hostnames[@]}"; do
    cat <<EOF
    - host: ${host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${name}
                port:
                  number: ${service_port}
EOF
  done
}

hostkit_expose_docker_app() {
  local name=""
  local port=""
  local namespace="default"
  local service_port="80"
  local host_ip=""
  local ingress_class="nginx"
  local tls_secret=""
  local kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  local remove=false
  local -a hostnames=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="${2:-}"
        shift 2
        ;;
      --port)
        port="${2:-}"
        shift 2
        ;;
      --host)
        hostnames+=("${2:-}")
        shift 2
        ;;
      --namespace)
        namespace="${2:-}"
        shift 2
        ;;
      --service-port)
        service_port="${2:-}"
        shift 2
        ;;
      --host-ip)
        host_ip="${2:-}"
        shift 2
        ;;
      --ingress-class)
        ingress_class="${2:-}"
        shift 2
        ;;
      --tls-secret)
        tls_secret="${2:-}"
        shift 2
        ;;
      --kubeconfig)
        kubeconfig="${2:-}"
        shift 2
        ;;
      --remove|-r)
        remove=true
        shift
        ;;
      -h|--help)
        hostkit_expose_docker_app_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_expose_docker_app_help
        exit 1
        ;;
    esac
  done

  if [[ -z "${name}" || -z "${port}" || ${#hostnames[@]} -eq 0 ]]; then
    hostkit_error "--name, --port, and at least one --host are required."
    hostkit_expose_docker_app_help
    exit 1
  fi

  if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    hostkit_error "Invalid --port: ${port} (must be 1-65535)"
    exit 1
  fi

  if ! [[ "${service_port}" =~ ^[0-9]+$ ]] || (( service_port < 1 || service_port > 65535 )); then
    hostkit_error "Invalid --service-port: ${service_port} (must be 1-65535)"
    exit 1
  fi

  hostkit_require_cmd kubectl

  if [[ -z "${host_ip}" ]]; then
    host_ip="$(hostkit_expose_detect_host_ip)"
  fi

  local kubectl_cmd=(kubectl --kubeconfig="${kubeconfig}")
  local yaml
  yaml="$(hostkit_expose_docker_app_render_yaml \
    "${name}" "${namespace}" "${host_ip}" "${port}" "${service_port}" \
    "${ingress_class}" "${tls_secret}" "${hostnames[@]}")"

  if [[ "${remove}" == "true" ]]; then
    hostkit_info "Removing Service/Endpoints/Ingress ${namespace}/${name}..."
    echo "${yaml}" | "${kubectl_cmd[@]}" delete -f - --ignore-not-found
    hostkit_success "Removed ${namespace}/${name} (Service, Endpoints, Ingress)."
    return 0
  fi

  hostkit_info "Applying Service/Endpoints/Ingress ${namespace}/${name} -> ${host_ip}:${port}..."
  echo "${yaml}" | "${kubectl_cmd[@]}" apply -f -

  hostkit_success "docker-compose app exposed via ingress-nginx."
  echo ""
  echo "Summary:"
  echo "   Name:         ${namespace}/${name}"
  echo "   Backend:      ${host_ip}:${port}"
  echo "   Hostnames:"
  local host
  for host in "${hostnames[@]}"; do
    echo "     - ${host}"
  done
  echo ""
  echo "Local test (via ingress-nginx):"
  for host in "${hostnames[@]}"; do
    echo "   curl -vk --resolve ${host}:443:127.0.0.1 https://${host}/"
  done
  echo ""
  echo "Public access: add hostname(s) to your Cloudflare Tunnel:"
  echo "   sudo hostkit tunnel install --name TUNNEL --hostname ${hostnames[0]} ..."
  hostkit_warn "Ensure the docker-compose app listens on 0.0.0.0:${port}, not 127.0.0.1 only."
}
