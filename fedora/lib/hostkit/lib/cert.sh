#!/usr/bin/env bash
# TLS: mkcert (local), ingress-nginx default cert, optional ACME via lego.

HOSTKIT_ACME_ENV="${HOSTKIT_ACME_ENV:-/etc/hostkit/acme.env}"
HOSTKIT_ACME_STATE="${HOSTKIT_ACME_STATE:-/var/lib/hostkit/acme}"

hostkit_cert_help() {
  cat <<'EOF'
hostkit cert - TLS certificate management

Subcommands:
  local            mkcert for internal/LAN hostnames (+ optional IPs)
  ingress-default  Point ingress-nginx at a TLS secret for catch-all HTTPS
  acme             Let's Encrypt via DNS-01 (lego + Porkbun)
  renew            Renew ACME certificates (for systemd timer)

Examples:
  hostkit cert local --out /path/.certs/prod --host app.example.staging --ip 192.168.1.10 \
    --secret ingress-tls-secret --namespace default
  hostkit cert ingress-default --secret default/ingress-tls-secret
  hostkit cert acme --provider porkbun --email you@example.com --host staging.example.com \
    --out /var/lib/hostkit/acme/staging --secret ingress-tls-public-secret
EOF
}

hostkit_cert() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    local)
      hostkit_cert_local "$@"
      ;;
    ingress-default)
      hostkit_cert_ingress_default "$@"
      ;;
    acme)
      hostkit_cert_acme "$@"
      ;;
    renew)
      hostkit_cert_renew "$@"
      ;;
    -h|--help|help|"")
      hostkit_cert_help
      [[ -n "${sub}" ]] || exit 1
      ;;
    *)
      hostkit_error "Unknown cert subcommand: ${sub}"
      hostkit_cert_help
      exit 1
      ;;
  esac
}

hostkit_cert_local_help() {
  cat <<'EOF'
hostkit cert local - generate mkcert TLS and optionally apply to Kubernetes

Usage:
  hostkit cert local --out DIR --host HOST... [options]

Options:
  --out DIR              Output directory for cert/key files
  --host HOST            DNS SAN (repeatable)
  --ip IP                IP SAN (repeatable)
  --cert-name NAME       Base filename without extension (default: ingress-tls)
  --secret NAME          Apply as kubectl TLS secret (optional)
  --namespace NS         Secret namespace (default: default)
  --force                Regenerate even if current cert is valid
  --kubeconfig PATH      KUBECONFIG for kubectl apply
  -h, --help
EOF
}

hostkit_cert_local() {
  local out_dir=""
  local cert_name="ingress-tls"
  local secret_name=""
  local namespace="default"
  local force=false
  local kubeconfig="${KUBECONFIG:-}"
  local -a hosts=()
  local -a ips=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        out_dir="${2:-}"
        shift 2
        ;;
      --host)
        hosts+=("${2:-}")
        shift 2
        ;;
      --ip)
        ips+=("${2:-}")
        shift 2
        ;;
      --cert-name)
        cert_name="${2:-}"
        shift 2
        ;;
      --secret)
        secret_name="${2:-}"
        shift 2
        ;;
      --namespace)
        namespace="${2:-}"
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      --kubeconfig)
        kubeconfig="${2:-}"
        shift 2
        ;;
      -h|--help)
        hostkit_cert_local_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_cert_local_help
        exit 1
        ;;
    esac
  done

  if [[ -z "${out_dir}" ]]; then
    hostkit_error "--out DIR is required."
    hostkit_cert_local_help
    exit 1
  fi
  if [[ ${#hosts[@]} -eq 0 && ${#ips[@]} -eq 0 ]]; then
    hostkit_error "At least one --host or --ip is required."
    exit 1
  fi

  local -a all_sans=("${hosts[@]}" "${ips[@]}")
  local crt="${out_dir}/${cert_name}.crt"
  local key="${out_dir}/${cert_name}.key"

  if [[ "${force}" != "true" ]] && hostkit_cert_local_is_current "${crt}" "${all_sans[@]}"; then
    hostkit_success "Certificate is current; skipping mkcert regeneration."
  else
    hostkit_cert_local_generate "${out_dir}" "${crt}" "${key}" "${hosts[@]}" "${ips[@]}"
  fi

  if [[ -n "${secret_name}" ]]; then
    hostkit_cert_apply_secret "${namespace}" "${secret_name}" "${crt}" "${key}" "${kubeconfig}"
  fi
}

hostkit_cert_local_generate() {
  local out_dir="$1"
  local crt="$2"
  local key="$3"
  shift 3
  local -a dns_hosts=()
  local -a ip_hosts=()
  local arg

  for arg in "$@"; do
    if [[ "${arg}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      ip_hosts+=("${arg}")
    else
      dns_hosts+=("${arg}")
    fi
  done

  hostkit_require_cmd mkcert "Install via: sudo bash linux/fedora/scripts/setup/26_mkcert.sh"
  mkdir -p "${out_dir}"

  local -a mkcert_args=(-key-file "${key}" -cert-file "${crt}")
  mkcert -install >/dev/null 2>&1 || true
  mkcert "${mkcert_args[@]}" "${dns_hosts[@]}" "${ip_hosts[@]}"
  chmod 600 "${key}"
  chmod 644 "${crt}"
  hostkit_success "Certificate written to ${out_dir}/"
}

hostkit_cert_local_is_current() {
  local crt="$1"
  shift
  local -a required=("$@")
  local renew_before="${TLS_RENEW_BEFORE_SECONDS:-2592000}"

  [[ -f "${crt}" ]] || return 1
  openssl x509 -checkend "${renew_before}" -noout -in "${crt}" >/dev/null 2>&1 || return 1
  hostkit_cert_signed_by_mkcert "${crt}" || return 1
  hostkit_cert_covers_sans "${crt}" "${required[@]}"
}

hostkit_cert_signed_by_mkcert() {
  local crt="$1"
  local ca_root ca_file

  command -v mkcert >/dev/null 2>&1 || return 1
  ca_root="$(mkcert -CAROOT 2>/dev/null || true)"
  ca_file="${ca_root}/rootCA.pem"
  [[ -f "${ca_file}" ]] || return 1
  openssl verify -CAfile "${ca_file}" "${crt}" >/dev/null 2>&1
}

hostkit_cert_covers_sans() {
  local crt="$1"
  shift
  local sans host

  sans="$(openssl x509 -in "${crt}" -noout -ext subjectAltName 2>/dev/null || true)"
  [[ -n "${sans}" ]] || return 1

  for host in "$@"; do
    if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      [[ "${sans}" == *"IP Address:${host}"* || "${sans}" == *"IP:${host}"* ]] || return 1
    else
      [[ "${sans}" == *"DNS:${host}"* ]] || return 1
    fi
  done
  return 0
}

hostkit_cert_apply_secret() {
  local namespace="$1"
  local secret_name="$2"
  local crt="$3"
  local key="$4"
  local kubeconfig="${5:-}"

  hostkit_require_cmd kubectl
  local kubectl_cmd=(kubectl)
  if [[ -n "${kubeconfig}" ]]; then
    kubectl_cmd=(kubectl --kubeconfig="${kubeconfig}")
  fi

  hostkit_info "Applying TLS secret ${namespace}/${secret_name}..."
  "${kubectl_cmd[@]}" create secret tls "${secret_name}" \
    --cert="${crt}" \
    --key="${key}" \
    --namespace="${namespace}" \
    --dry-run=client -o yaml | "${kubectl_cmd[@]}" apply -f -
  hostkit_success "TLS secret applied."
}

hostkit_cert_ingress_default() {
  local secret_ref=""
  local ingress_ns="${INGRESS_NAMESPACE:-ingress-nginx}"
  local ingress_deploy="${INGRESS_DEPLOYMENT:-ingress-nginx-controller}"
  local kubeconfig="${KUBECONFIG:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --secret)
        secret_ref="${2:-}"
        shift 2
        ;;
      --ingress-namespace)
        ingress_ns="${2:-}"
        shift 2
        ;;
      --ingress-deployment)
        ingress_deploy="${2:-}"
        shift 2
        ;;
      --kubeconfig)
        kubeconfig="${2:-}"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
hostkit cert ingress-default - configure ingress-nginx default SSL certificate

Usage:
  hostkit cert ingress-default --secret NAMESPACE/SECRET_NAME [options]
EOF
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  if [[ -z "${secret_ref}" ]]; then
    hostkit_error "--secret NAMESPACE/NAME is required."
    exit 1
  fi

  hostkit_require_cmd kubectl
  local kubectl_cmd=(kubectl)
  [[ -n "${kubeconfig}" ]] && kubectl_cmd=(kubectl --kubeconfig="${kubeconfig}")

  local ns="${secret_ref%%/*}"
  local secret_name="${secret_ref#*/}"
  local arg="--default-ssl-certificate=${secret_ref}"

  if ! "${kubectl_cmd[@]}" get secret "${secret_name}" -n "${ns}" >/dev/null 2>&1; then
    hostkit_warn "TLS secret ${secret_ref} not found; skipping."
    return 0
  fi

  if ! "${kubectl_cmd[@]}" get deployment "${ingress_deploy}" -n "${ingress_ns}" >/dev/null 2>&1; then
    hostkit_warn "Deployment ${ingress_ns}/${ingress_deploy} not found; skipping."
    return 0
  fi

  local existing
  existing="$("${kubectl_cmd[@]}" get deployment "${ingress_deploy}" -n "${ingress_ns}" \
    -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || true)"

  if [[ "${existing}" == *"${arg}"* ]]; then
    hostkit_success "ingress-nginx already uses ${arg}"
    return 0
  fi

  hostkit_info "Configuring ingress-nginx default TLS certificate: ${secret_ref}"
  "${kubectl_cmd[@]}" patch deployment "${ingress_deploy}" -n "${ingress_ns}" --type=json \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"${arg}\"}]"

  hostkit_info "Waiting for ingress-nginx controller rollout..."
  "${kubectl_cmd[@]}" rollout status "deployment/${ingress_deploy}" -n "${ingress_ns}" --timeout=120s
  hostkit_success "ingress-nginx default certificate configured (${secret_ref})."
}

hostkit_cert_acme_help() {
  cat <<'EOF'
hostkit cert acme - obtain Let's Encrypt certificate via DNS-01

Usage:
  hostkit cert acme --provider porkbun --email EMAIL --host HOST... [options]

Options:
  --provider NAME        DNS provider (only porkbun supported today)
  --email EMAIL          ACME account email
  --host HOST            Certificate hostname (repeatable)
  --out DIR              lego data/output directory
  --secret NAME          Apply cert as kubectl TLS secret
  --namespace NS         Secret namespace (default: default)
  --staging              Use Let's Encrypt staging CA
  --env-file PATH        Porkbun credentials (default: /etc/hostkit/acme.env)
  --kubeconfig PATH      KUBECONFIG for kubectl apply
  -h, --help

Credentials file format (/etc/hostkit/acme.env):
  PORKBUN_API_KEY=...
  PORKBUN_SECRET_API_KEY=...
EOF
}

hostkit_cert_acme() {
  local provider=""
  local email=""
  local out_dir=""
  local secret_name=""
  local namespace="default"
  local staging=false
  local env_file="${HOSTKIT_ACME_ENV}"
  local kubeconfig="${KUBECONFIG:-}"
  local -a hosts=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)
        provider="${2:-}"
        shift 2
        ;;
      --email)
        email="${2:-}"
        shift 2
        ;;
      --host)
        hosts+=("${2:-}")
        shift 2
        ;;
      --out)
        out_dir="${2:-}"
        shift 2
        ;;
      --secret)
        secret_name="${2:-}"
        shift 2
        ;;
      --namespace)
        namespace="${2:-}"
        shift 2
        ;;
      --staging)
        staging=true
        shift
        ;;
      --env-file)
        env_file="${2:-}"
        shift 2
        ;;
      --kubeconfig)
        kubeconfig="${2:-}"
        shift 2
        ;;
      -h|--help)
        hostkit_cert_acme_help
        return 0
        ;;
      *)
        hostkit_error "Unknown option: $1"
        hostkit_cert_acme_help
        exit 1
        ;;
    esac
  done

  if [[ "${provider}" != "porkbun" ]]; then
    hostkit_error "--provider porkbun is required."
    exit 1
  fi
  if [[ -z "${email}" || ${#hosts[@]} -eq 0 ]]; then
    hostkit_error "--email and at least one --host are required."
    exit 1
  fi
  if [[ -z "${out_dir}" ]]; then
    out_dir="${HOSTKIT_ACME_STATE}/$(echo "${hosts[0]}" | tr '.' '_')"
  fi

  hostkit_require_cmd lego "Install via: sudo bash linux/fedora/scripts/setup/30_hostkit.sh"
  if [[ ! -f "${env_file}" ]]; then
    hostkit_error "ACME credentials not found at ${env_file}"
    hostkit_info "Create it with PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY (chmod 600)."
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "${env_file}"
  set +a

  mkdir -p "${out_dir}"
  local -a lego_args=(--dns porkbun --email "${email}" --path "${out_dir}" --accept-tos)
  if [[ "${staging}" == "true" ]]; then
    lego_args+=(--server https://acme-staging-v02.api.letsencrypt.org/directory)
  fi

  local host
  for host in "${hosts[@]}"; do
    lego_args+=(-d "${host}")
  done

  hostkit_info "Requesting ACME certificate for: ${hosts[*]}"
  lego run "${lego_args[@]}"

  local primary="${hosts[0]}"
  local crt="${out_dir}/certificates/${primary}.crt"
  local key="${out_dir}/certificates/${primary}.key"

  if [[ ! -f "${crt}" || ! -f "${key}" ]]; then
    hostkit_error "lego did not produce expected cert files under ${out_dir}/certificates/"
    exit 1
  fi

  if [[ -n "${secret_name}" ]]; then
    hostkit_cert_apply_secret "${namespace}" "${secret_name}" "${crt}" "${key}" "${kubeconfig}"
  fi

  hostkit_cert_write_renew_config "${out_dir}" "${email}" "${secret_name}" "${namespace}" "${staging}" "${hosts[@]}"
  hostkit_success "ACME certificate obtained for ${hosts[*]}"
}

hostkit_cert_renew() {
  hostkit_require_cmd lego
  local renew_conf="${HOSTKIT_ACME_STATE}/renew.conf"
  local env_file="${HOSTKIT_ACME_ENV}"

  if [[ ! -f "${renew_conf}" ]]; then
    hostkit_info "No ACME renew config at ${renew_conf}; nothing to renew."
    return 0
  fi

  # shellcheck disable=SC1090
  source "${renew_conf}"

  if [[ -z "${HOSTKIT_ACME_OUT:-}" ]]; then
    hostkit_warn "Invalid renew config; skipping."
    return 0
  fi

  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a
  fi

  hostkit_info "Renewing ACME certificates in ${HOSTKIT_ACME_OUT}..."
  lego --path "${HOSTKIT_ACME_OUT}" renew

  if [[ -n "${HOSTKIT_ACME_SECRET:-}" && -n "${HOSTKIT_ACME_HOSTS:-}" ]]; then
    local primary="${HOSTKIT_ACME_HOSTS%% *}"
    local crt="${HOSTKIT_ACME_OUT}/certificates/${primary}.crt"
    local key="${HOSTKIT_ACME_OUT}/certificates/${primary}.key"
    if [[ -f "${crt}" && -f "${key}" ]]; then
      hostkit_cert_apply_secret \
        "${HOSTKIT_ACME_NAMESPACE:-default}" \
        "${HOSTKIT_ACME_SECRET}" \
        "${crt}" \
        "${key}" \
        "${KUBECONFIG:-}"
    fi
  fi

  hostkit_success "ACME renewal finished."
}

hostkit_cert_write_renew_config() {
  local out_dir="$1"
  local email="$2"
  local secret_name="$3"
  local namespace="$4"
  local staging="$5"
  shift 5
  local -a hosts=("$@")

  mkdir -p "${HOSTKIT_ACME_STATE}"
  cat > "${HOSTKIT_ACME_STATE}/renew.conf" <<EOF
HOSTKIT_ACME_OUT="${out_dir}"
HOSTKIT_ACME_EMAIL="${email}"
HOSTKIT_ACME_SECRET="${secret_name}"
HOSTKIT_ACME_NAMESPACE="${namespace}"
HOSTKIT_ACME_STAGING="${staging}"
HOSTKIT_ACME_HOSTS="${hosts[*]}"
EOF
  chmod 600 "${HOSTKIT_ACME_STATE}/renew.conf"
}
