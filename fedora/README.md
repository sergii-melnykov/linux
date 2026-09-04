# Fedora Dev Setup

A complete, modular automated setup for Fedora workstations. This setup includes development tools, containerization, virtualization, NVIDIA drivers, and productivity applications.

## 📦 What's Included

### System & Repositories

- **System Updates** - Full system update via DNF
- **RPM Fusion** - Free and non-free repositories for additional software

### Development Tools

- **Git** - Version control with user configuration
- **Node.js** - Via NVM (Node Version Manager) with latest LTS
- **Python** - Python 3 and pip package manager
- **VS Code** - Microsoft's code editor

### Containerization & Orchestration

- **Docker Engine** - Container runtime with Docker Compose plugin
- **kubectl** - Kubernetes command-line tool
- **Helm** - Kubernetes package manager (Helm 4 from Fedora repos)
- **Minikube** - Local Kubernetes cluster (dev)
- **Skaffold** - Kubernetes development workflow tool
- **k3s** - Lightweight Kubernetes binary for home-server production (install-only; cluster provisioning is in app-skeleton)
- **mkcert** - Local TLS CA for `*.local` ingress hostnames
- **Docker Registry** - Local, app-agnostic image registry (systemd, port 5000, Web UI on port 5080, auto-starts on boot)
- **hostkit** - Agnostic CLI for k3s cluster bring-up, mkcert/ACME TLS, firewalld exposure, Cloudflare Tunnel
- **cloudflared** - Cloudflare Tunnel client (opt-in tunnel provisioning via hostkit)
- **jq / yq** - JSON/YAML CLI tools for inspecting deploy artifacts and values files

#### Local Docker Registry

`28_registry.sh` installs a standalone `registry:2` container as a systemd service, plus a
[Joxit Docker Registry UI](https://github.com/Joxit/docker-registry-ui) container for browsing
images in the browser. It belongs to no specific project - any tool on this host
(`docker push`/`pull`, Skaffold, k3s, Minikube, ...) can use it at `localhost:5000`.

- Data persisted at `/var/lib/docker-registry/`
- Auto-starts on boot via `docker-registry.service` and `docker-registry-ui.service`
- Web UI at `http://localhost:5080` (proxies API calls to avoid CORS issues)
- Adds `localhost:5000` to `insecure-registries` in `/etc/docker/daemon.json` automatically (HTTP, no TLS) and restarts Docker
- Override port/name via `REGISTRY_PORT`, `REGISTRY_DATA_DIR`, `REGISTRY_NAME`, `REGISTRY_UI_PORT`, `REGISTRY_UI_NAME` env vars before running the script

```bash
# Management
systemctl status docker-registry
systemctl status docker-registry-ui
journalctl -u docker-registry -f
journalctl -u docker-registry-ui -f
curl http://localhost:5000/v2/
xdg-open http://localhost:5080   # or open in browser manually
```

#### Kubernetes Deployment (home-server prod)

These scripts install the **client tools and host prerequisites** needed by [app-skeleton/deploy-prod.sh](https://github.com/sergii-melnykov/app-skeleton) (k3s + Skaffold/Helm). They do **not** start the cluster. The local registry (above) is provisioned separately and is not app-skeleton-specific.

| Script | What it does |
|--------|--------------|
| `26_mkcert.sh` | Installs mkcert + nss-tools; runs `mkcert -install` as `$SUDO_USER` |
| `27_k3s.sh` | Host prep (firewalld, NetworkManager, kernel modules) + k3s binary (not started) |
| `28_registry.sh` | Local Docker registry + Web UI (systemd, ports 5000/5080, auto-starts on boot) |
| `30_hostkit.sh` | Installs **hostkit** CLI to `/usr/local/bin` (+ optional **lego** for Let's Encrypt) |
| `31_cloudflared.sh` | Installs **cloudflared** package (tunnel setup is opt-in via hostkit) |

**After `setup.sh`, start the cluster:**

```bash
sudo hostkit cluster up    # enable/start k3s, ingress-nginx, metrics-server
```

**Stable k3s node name (reboot-safe local-path volumes):**

k3s node identity is pinned to `k3s-home` by default (independent of OS hostname) via `/etc/rancher/k3s/config.yaml`. This prevents local-path PVs from becoming unschedulable when the machine hostname changes after reboot.

```bash
export K3S_NODE_NAME=k3s-home   # optional override (before first cluster up)
sudo hostkit cluster up
```

If the cluster was created before node-name pinning or node identity drifted, reset and redeploy (destroys cluster data):

```bash
sudo hostkit cluster reset --force --up
# from app-skeleton:
sudo ./bootstrap-scripts/prod/reset-k3s.sh --force
./deploy-prod.sh
```

`deploy-prod.sh` verifies the Ready node matches `K3S_NODE_NAME` before deploy.

**From the app-skeleton repo:**

```bash
cp k8s/helm/app-skeleton/values-prod-secrets.yaml.example k8s/helm/app-skeleton/values-prod-secrets.yaml
./deploy-prod.sh
```

(`setup-k3s.sh` wraps `hostkit cluster up`; `reset-k3s.sh` wipes and recreates the cluster.)

**Host prep in `27_k3s.sh`:**

- firewalld: trusts pod/service CIDRs (`10.42.0.0/16`, `10.43.0.0/16`), opens 6443/80/443
- NetworkManager: ignores `cni0`, `flannel*`, `veth*` interfaces
- Kernel modules: persists `br_netfilter` and `overlay`
- k3s resolver: `--resolv-conf=/run/systemd/resolve/resolv.conf`
- k3s node name: `--node-name=k3s-home` (override with `K3S_NODE_NAME`; canonical config in `/etc/rancher/k3s/config.yaml` after `hostkit cluster up`)

The local registry is already running after `setup.sh` (started by `28_registry.sh`). No VM required — k3s runs as a systemd service on bare metal.

#### Expose a docker-compose app via ingress-nginx

Use **hostkit** to route a docker-compose application (listening on a host port) through the same `ingress-nginx` and Cloudflare Tunnel as regular k8s apps:

```bash
# Wire myapp (host port 8081) to myapp.example.com via ingress-nginx
hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com

# With TLS secret and custom namespace
hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com \
  --tls-secret myapp-tls --namespace apps

# Remove the generated Service/Endpoints/Ingress
hostkit expose docker-app --name myapp --port 8081 --host myapp.example.com --remove
```

Requirements:
- k3s cluster running with ingress-nginx (`sudo hostkit cluster up`)
- docker-compose app must listen on `0.0.0.0:PORT`, not `127.0.0.1` only
- Add the hostname to your Cloudflare Tunnel (`hostkit tunnel install --hostname ...`)

Local test before tunnel:

```bash
curl -vk --resolve myapp.example.com:443:127.0.0.1 https://myapp.example.com/
```

#### hostkit — cluster, TLS, tunnels

Installed by `30_hostkit.sh` to `/usr/local/bin/hostkit`. App-agnostic; any project on this host can use it.

| Command | Purpose |
|---------|---------|
| `hostkit cluster up` | Start k3s, configure registry mirror, install ingress-nginx + metrics-server |
| `hostkit cert local` | mkcert for internal/LAN hostnames → optional k8s TLS secret |
| `hostkit cert acme` | Let's Encrypt via Porkbun DNS-01 (requires `/etc/hostkit/acme.env`) |
| `hostkit cert ingress-default` | ingress-nginx catch-all cert for HTTPS by IP |
| `hostkit expose docker-app` | Wire docker-compose app (host port) into ingress-nginx |
| `hostkit tunnel install` | cloudflared systemd service (token or config mode) |

**Cloudflare Tunnel** (after `31_cloudflared.sh`):

```bash
sudo hostkit tunnel install --token YOUR_TUNNEL_TOKEN
```

Config mode and Porkbun CNAME steps: see app-skeleton `docs/how-to-expose-app-publicly.md`.

#### app-skeleton: customer app by IP (k3s)

For the home-server k3s deploy, use app-skeleton's LAN setup (ingress + TLS + CORS by IP):

```bash
cd app-skeleton
sudo ./bootstrap-scripts/prod/setup-lan-access.sh   # opens :443, writes values-prod-lan.yaml
./deploy-prod.sh
```

Then open `https://<lan-ip>/` from any device on the same Wi‑Fi (accept the browser cert warning).
See `app-skeleton/bootstrap-scripts/prod/LAN-ACCESS.md` for details and limitations.

### Virtualization

- **VirtualBox** - With Secure Boot MOK key setup and kernel module signing

### Applications

- **Google Chrome** - Web browser
- **Google Antigravity** - AI-powered IDE
- **Viber** - Messaging application
- **Telegram** - Messaging application

### Desktop Environment

- **GNOME Extensions** - Including:
  - Vitals (system monitoring)
  - Sound Input & Output Device Chooser
  - Tiling Shell (window management)

### Graphics & AI

- **NVIDIA Drivers** - Automatic detection and installation for NVIDIA GPUs
- **GPU Application Config** - Configures Chrome and VS Code to use discrete GPU
- **Ollama** - Local AI model runner
- **Qdrant** - Vector database with FastEmbed GPU-accelerated embeddings (auto-starts on boot)

### Security

- **SSH** - SSH key generation and configuration

---

## 🚀 Quick Install

### Option 1: Local Install

```bash
git clone https://github.com/sergii-melnykov/linux.git
cd linux/fedora
sudo bash setup.sh
```

---

## 📋 Script Execution Order

The scripts in `scripts/setup/` run in numerical order (00-31, skipping 29). The order is optimized for dependencies:

1. **00_update.sh** - System updates
2. **01_rpm_fusion.sh** - Third-party repositories
3. **02_tools.sh** - wget, unzip, xclip, jq, yq
4. **03_git.sh** - Version control
5. **04_nodejs.sh** - Node.js via NVM
6. **05_python.sh** - Python environment
7. **06_vscode.sh** - Code editor
8. **07_ssh.sh** - SSH setup
9. **08_virtualbox.sh** - Virtualization platform
10. **09_chrome.sh** - Web browser
11. **11_skaffold.sh** - Kubernetes dev tool
12. **12_docker.sh** - Container runtime
13. **13_kubectl.sh** - Kubernetes CLI
14. **14_minikube.sh** - Local Kubernetes (dev)
15. **15_gnome_extensions.sh** - Desktop extensions
16. **16_viber.sh** - Messaging app
17. **17_telegram.sh** - Messaging app
18. **18_nvidia_drivers.sh** - GPU drivers (auto-detects NVIDIA)
19. **19_gpu_app_config.sh** - GPU application preferences
20. **20_ollama.sh** - AI model runner
21. **21_helm.sh** - Helm package manager
22. **22_terminal.sh** - Terminal customization
23. **23_wireshark.sh** - Network analyzer
24. **24_rtk.sh** - RTK tooling
25. **25_qdrant.sh** - Vector database with GPU-accelerated FastEmbed embeddings
26. **26_mkcert.sh** - Local TLS CA for production ingress
27. **27_k3s.sh** - k3s binary + host prep for home-server cluster
28. **28_registry.sh** - Local Docker registry + Web UI (systemd, auto-starts on boot)
29. **30_hostkit.sh** - hostkit CLI (cluster, TLS, exposure)
30. **31_cloudflared.sh** - Cloudflare Tunnel client

---

## ⚙️ Features

### Modular Design

Setup scripts live in `scripts/setup/` and run via `setup.sh` in numeric order. Operational tasks (start cluster, TLS, tunnels) use **hostkit** after setup.

You can:

- Run the full setup: `sudo bash setup.sh`
- Run a single setup component: `sudo ./scripts/setup/12_docker.sh`
- Comment out or remove setup scripts you don't need
- Add your own numbered scripts to `scripts/setup/` (e.g., `32_custom.sh`)

### Error Resilience

The main `setup.sh` script continues execution even if individual scripts fail, reporting all failures at the end.

### User-Aware Installation

Scripts detect when run with `sudo` and configure settings for the actual user (not root), including:

- Docker group membership
- mkcert root CA installation
- GNOME extensions
- GPU application preferences

### Hardware Detection

- **NVIDIA GPU**: Automatically detects and skips driver installation if no NVIDIA GPU is present
- **Secure Boot**: VirtualBox setup includes MOK key generation for Secure Boot systems

---

## 🔧 Requirements

- Fedora (tested on recent versions)
- Sudo/root access
- Internet connection

---

## 📝 Post-Installation Notes

### Required Actions

1. **Reboot** - Required for:
   - VirtualBox kernel modules
   - NVIDIA drivers
   - Docker group membership to take effect

2. **VirtualBox Secure Boot** - After reboot:
   - Select "Enroll MOK" in the boot menu
   - Enter the password you set during installation
   - Continue to boot

3. **GNOME Extensions** - After reboot:
   - Open the "Extensions" app
   - Enable/configure installed extensions

### Verification Commands

```bash
# Docker
docker --version
docker run hello-world

# Node.js
nvm --version
node --version

# Kubernetes tools
kubectl version --client
helm version
skaffold version
minikube version
k3s --version          # binary installed; cluster not started until setup-k3s.sh
mkcert -CAROOT         # should point to ~/.local/share/mkcert (not /root)
systemctl status docker-registry      # local registry, should be active/running
systemctl status docker-registry-ui   # Web UI, should be active/running
curl http://localhost:5000/v2/        # should return {}
curl http://localhost:5080/           # registry Web UI
jq --version
yq --version

# NVIDIA (if applicable)
nvidia-smi
```

---

## 🛠️ Customization

To modify what gets installed:

1. Edit `setup.sh` to skip specific scripts
2. Modify individual scripts in `scripts/setup/`
3. Add your own numbered setup scripts (e.g., `scripts/setup/32_custom.sh`)

---

## 📄 License

MIT License - Feel free to use and modify
