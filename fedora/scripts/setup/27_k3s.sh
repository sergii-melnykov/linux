#!/usr/bin/env bash
set -e

echo "☸️  Installing k3s (binary only, host prep)..."

K3S_RESOLV_CONF="${K3S_RESOLV_CONF:-/run/systemd/resolve/resolv.conf}"
K3S_NODE_NAME="${K3S_NODE_NAME:-k3s-home}"
# Pin node name so local-path PVs survive OS hostname changes after reboot.
# Canonical config is written by `hostkit cluster up` to /etc/rancher/k3s/config.yaml.
K3S_EXEC_ARGS="server --node-name=${K3S_NODE_NAME} --disable=traefik --write-kubeconfig-mode=644 --resolv-conf=${K3S_RESOLV_CONF}"

configure_firewalld() {
    if ! systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "ℹ️  firewalld is not active; skipping firewall rules."
        return 0
    fi

    echo "Configuring firewalld for k3s..."
    firewall-cmd --permanent --add-source=10.42.0.0/16 || true   # pod CIDR
    firewall-cmd --permanent --add-source=10.43.0.0/16 || true   # service CIDR
    firewall-cmd --permanent --add-port=6443/tcp || true          # kube API
    firewall-cmd --reload || true
    echo "✅ firewalld configured for k3s."
}

configure_networkmanager() {
    local nm_conf="/etc/NetworkManager/conf.d/99-k3s-unmanaged.conf"

    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        echo "ℹ️  NetworkManager is not active; skipping unmanaged-devices drop-in."
        return 0
    fi

    echo "Configuring NetworkManager to ignore k3s CNI interfaces..."
    mkdir -p /etc/NetworkManager/conf.d
    cat > "${nm_conf}" <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cni0;interface-name:flannel*;interface-name:veth*
EOF
    systemctl reload NetworkManager 2>/dev/null || true
    echo "✅ Wrote ${nm_conf}"
}

configure_kernel_modules() {
    local modules_conf="/etc/modules-load.d/k3s.conf"

    echo "Persisting br_netfilter and overlay kernel modules..."
    cat > "${modules_conf}" <<'EOF'
br_netfilter
overlay
EOF
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true
    echo "✅ Kernel modules configured in ${modules_conf}"
}

install_k3s_binary() {
    if command -v k3s >/dev/null 2>&1; then
        echo "ℹ️  k3s is already installed: $(k3s --version 2>/dev/null || echo 'version unknown')"
        return 0
    fi

    echo "Installing k3s binary (not starting service)..."
    dnf install -y container-selinux

    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_SKIP_START=true \
        INSTALL_K3S_SKIP_ENABLE=true \
        INSTALL_K3S_EXEC="${K3S_EXEC_ARGS}" \
        sh -

    echo "✅ k3s binary installed (service not started)."
}

configure_firewalld
configure_networkmanager
configure_kernel_modules
install_k3s_binary

echo ""
echo "📝 Next steps:"
echo "   sudo bash linux/fedora/scripts/setup/30_hostkit.sh   # if hostkit is not installed yet"
echo "   sudo hostkit cluster up                          # start k3s + ingress-nginx"
echo ""
echo "   Reset cluster (wipes all workloads + local-path data, then recreates):"
echo "   sudo hostkit cluster reset --force --up"
echo "   # or from app-skeleton: sudo ./bootstrap-scripts/prod/reset-k3s.sh --force"
echo ""
echo "   Redeploy after reset:"
echo "   cd langfuse-platform && ./deploy.sh --reset-data --force"
echo "   cd app-skeleton && ./deploy.sh"
echo ""
echo "✅ k3s host prep complete."
