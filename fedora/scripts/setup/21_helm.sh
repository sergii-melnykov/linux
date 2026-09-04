#!/usr/bin/env bash
set -e

echo "⎈ Installing Helm v4+, helm-diff plugin, and helmfile..."

HELM_INSTALL_DIR="${HELM_INSTALL_DIR:-/usr/local/bin}"
HELMFILE_INSTALL_DIR="${HELMFILE_INSTALL_DIR:-/usr/local/bin}"

# helm version --short prints e.g. `v4.2.3+gabcdef`; extract the leading `vMAJOR`.
helm_major_version() {
    helm version --short 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' | head -n1
}

install_helm() {
    local current
    current="$(helm_major_version 2>/dev/null || true)"

    if [[ -n "${current}" && "${current}" -ge 4 ]]; then
        echo "ℹ️  Helm v${current} is already installed: $(helm version --short 2>/dev/null)"
        return 0
    fi

    if [[ -n "${current}" ]]; then
        echo "ℹ️  Helm is installed but v${current} (< v4); upgrading via official installer..."
    else
        echo "Installing Helm via official installer (get-helm-4)..."
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "⚠️  curl is required to fetch the Helm installer."
        exit 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -dt helm-installer-XXXXXX)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    curl -fsSL -o "${tmp_dir}/get_helm.sh" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 "${tmp_dir}/get_helm.sh"

    # Pin a minimum v4 release when DESIRED_VERSION is not provided.
    # The installer fetches the latest v4 release by default.
    if [[ -z "${DESIRED_VERSION:-}" ]]; then
        "${tmp_dir}/get_helm.sh" --no-sudo
    else
        "${tmp_dir}/get_helm.sh" --no-sudo --version "${DESIRED_VERSION}"
    fi

    echo "✅ Helm installed: $(helm version --short 2>/dev/null)"
}

install_helm_diff() {
    if helm diff version >/dev/null 2>&1; then
        echo "ℹ️  helm-diff plugin is already installed: $(helm diff version 2>/dev/null | head -n1)"
        return 0
    fi

    echo "Installing helm-diff plugin..."
    helm plugin install https://github.com/databus23/helm-diff
    echo "✅ helm-diff installed: $(helm diff version 2>/dev/null | head -n1)"
}

install_helmfile() {
    if command -v helmfile >/dev/null 2>&1; then
        echo "ℹ️  helmfile is already installed: $(helmfile --version 2>/dev/null || echo 'version unknown')"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "⚠️  curl is required to fetch helmfile."
        exit 1
    fi

    echo "Detecting latest helmfile release..."
    local latest_tag
    latest_tag="$(curl -fsSL https://api.github.com/repos/helmfile/helmfile/releases/latest \
        | sed -E 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n1)"

    if [[ -z "${latest_tag}" ]]; then
        echo "⚠️  Could not determine the latest helmfile release."
        exit 1
    fi

    local version="${latest_tag#v}"
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        i386|i686)     arch="386"   ;;
        *)
            echo "⚠️  Unsupported architecture for helmfile: ${arch}"
            exit 1
            ;;
    esac

    local tmp_dir
    tmp_dir="$(mktemp -dt helmfile-installer-XXXXXX)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    local url="https://github.com/helmfile/helmfile/releases/download/v${version}/helmfile_${version}_linux_${arch}.tar.gz"
    echo "Downloading helmfile ${latest_tag} (${arch})..."
    curl -fsSL -o "${tmp_dir}/helmfile.tar.gz" "${url}"
    tar -xzf "${tmp_dir}/helmfile.tar.gz" -C "${tmp_dir}"

    install -m 0755 "${tmp_dir}/helmfile" "${HELMFILE_INSTALL_DIR}/helmfile"
    echo "✅ helmfile installed: $(${HELMFILE_INSTALL_DIR}/helmfile --version 2>/dev/null)"
}

install_helm
install_helm_diff
install_helmfile

echo ""
echo "📝 Next steps:"
echo "   helm version        # verify Helm v4+"
echo "   helm diff version   # verify helm-diff plugin"
echo "   helmfile version    # verify helmfile"
