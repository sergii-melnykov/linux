#!/usr/bin/env bash
set -e

echo "📦 Installing local Docker Registry + Web UI (systemd)..."

# This registry is a generic, app-agnostic build cache for anything on this
# host that needs to push/pull images (Kubernetes clusters, Skaffold, plain
# docker push/pull, etc). It has no knowledge of any specific project.

REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_DATA_DIR="${REGISTRY_DATA_DIR:-/var/lib/docker-registry}"
REGISTRY_NAME="${REGISTRY_NAME:-docker-registry}"
REGISTRY_UI_PORT="${REGISTRY_UI_PORT:-5080}"
REGISTRY_UI_NAME="${REGISTRY_UI_NAME:-docker-registry-ui}"
REGISTRY_UI_IMAGE="${REGISTRY_UI_IMAGE:-joxit/docker-registry-ui:2}"
REGISTRY_HOST="localhost:${REGISTRY_PORT}"
REGISTRY_UI_URL="http://localhost:${REGISTRY_UI_PORT}"

# ──────────────────────────────────────────────
# 1. Check Docker availability
# ──────────────────────────────────────────────
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please run 12_docker.sh first."
    exit 1
fi

if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    systemctl start docker
fi

# ──────────────────────────────────────────────
# 2. Create storage directory
# ──────────────────────────────────────────────
echo "Creating registry data directory..."
mkdir -p "${REGISTRY_DATA_DIR}"

# ──────────────────────────────────────────────
# 3. Pull registry Docker image
# ──────────────────────────────────────────────
echo "Pulling registry:2 image..."
docker pull registry:2

echo "Pulling ${REGISTRY_UI_IMAGE} image..."
docker pull "${REGISTRY_UI_IMAGE}"

# ──────────────────────────────────────────────
# 4. Create systemd service unit
# ──────────────────────────────────────────────
echo "Creating systemd service unit..."
cat > "/etc/systemd/system/${REGISTRY_NAME}.service" << UNIT
[Unit]
Description=Local Docker Registry (registry:2)
Documentation=https://docs.docker.com/registry/
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=exec
Restart=unless-stopped
RestartSec=10s
TimeoutStartSec=60

ExecStartPre=-/usr/bin/docker stop ${REGISTRY_NAME}
ExecStartPre=-/usr/bin/docker rm ${REGISTRY_NAME}
ExecStart=/usr/bin/docker run \\
    --name ${REGISTRY_NAME} \\
    --rm \\
    -p ${REGISTRY_PORT}:5000 \\
    -v ${REGISTRY_DATA_DIR}:/var/lib/registry \\
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \\
    registry:2

ExecStop=/usr/bin/docker stop -t 10 ${REGISTRY_NAME}
ExecStopPost=-/usr/bin/docker rm ${REGISTRY_NAME}

[Install]
WantedBy=multi-user.target
UNIT

# ──────────────────────────────────────────────
# 5. Create systemd service unit for Web UI
# ──────────────────────────────────────────────
echo "Creating registry Web UI systemd service unit..."
cat > "/etc/systemd/system/${REGISTRY_UI_NAME}.service" << UNIT
[Unit]
Description=Local Docker Registry Web UI (joxit/docker-registry-ui)
Documentation=https://github.com/Joxit/docker-registry-ui
Requires=docker.service ${REGISTRY_NAME}.service
After=docker.service ${REGISTRY_NAME}.service network-online.target
Wants=network-online.target

[Service]
Type=exec
Restart=unless-stopped
RestartSec=10s
TimeoutStartSec=60

ExecStartPre=-/usr/bin/docker stop ${REGISTRY_UI_NAME}
ExecStartPre=-/usr/bin/docker rm ${REGISTRY_UI_NAME}
ExecStart=/usr/bin/docker run \\
    --name ${REGISTRY_UI_NAME} \\
    --rm \\
    -p ${REGISTRY_UI_PORT}:80 \\
    --add-host=host.docker.internal:host-gateway \\
    -e SINGLE_REGISTRY=true \\
    -e REGISTRY_TITLE=Local-Docker-Registry \\
    -e REGISTRY_URL=${REGISTRY_UI_URL} \\
    -e NGINX_PROXY_PASS_URL=http://host.docker.internal:${REGISTRY_PORT} \\
    -e DELETE_IMAGES=true \\
    -e REGISTRY_SECURED=false \\
    ${REGISTRY_UI_IMAGE}

ExecStop=/usr/bin/docker stop -t 10 ${REGISTRY_UI_NAME}
ExecStopPost=-/usr/bin/docker rm ${REGISTRY_UI_NAME}

[Install]
WantedBy=multi-user.target
UNIT

# ──────────────────────────────────────────────
# 6. Trust the registry as insecure (HTTP, no TLS)
# ──────────────────────────────────────────────
DAEMON_JSON="/etc/docker/daemon.json"
echo "Configuring Docker to trust ${REGISTRY_HOST} as an insecure registry..."
mkdir -p "$(dirname "$DAEMON_JSON")"

if [ ! -f "$DAEMON_JSON" ]; then
    echo "{}" > "$DAEMON_JSON"
fi

if command -v jq &> /dev/null && jq -e . "$DAEMON_JSON" &> /dev/null; then
    if jq -e --arg host "$REGISTRY_HOST" '.["insecure-registries"] // [] | index($host)' "$DAEMON_JSON" &> /dev/null; then
        echo "ℹ️  ${REGISTRY_HOST} already trusted in ${DAEMON_JSON}."
    else
        TMP_JSON="$(mktemp)"
        jq --arg host "$REGISTRY_HOST" \
           '.["insecure-registries"] = ((.["insecure-registries"] // []) + [$host] | unique)' \
           "$DAEMON_JSON" > "$TMP_JSON"
        mv "$TMP_JSON" "$DAEMON_JSON"
        echo "✅ Added ${REGISTRY_HOST} to insecure-registries in ${DAEMON_JSON}."
        echo "Restarting Docker to apply daemon.json changes..."
        systemctl restart docker
    fi
else
    echo "⚠️  jq unavailable or ${DAEMON_JSON} is not valid JSON - skipping automatic edit."
    echo "   Add \"${REGISTRY_HOST}\" to \"insecure-registries\" in ${DAEMON_JSON} manually, then:"
    echo "   sudo systemctl restart docker"
fi

# ──────────────────────────────────────────────
# 7. Reload systemd, enable and start
# ──────────────────────────────────────────────
echo "Enabling and starting registry services..."
systemctl daemon-reload
systemctl enable "${REGISTRY_NAME}.service" "${REGISTRY_UI_NAME}.service"
systemctl start "${REGISTRY_NAME}.service"
systemctl start "${REGISTRY_UI_NAME}.service"

# ──────────────────────────────────────────────
# 8. Wait for health check and verify
# ──────────────────────────────────────────────
echo "Waiting for registry to become healthy..."
for i in $(seq 1 30); do
    if curl -sf "http://${REGISTRY_HOST}/v2/" > /dev/null 2>&1; then
        echo "✅ Registry is healthy!"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "⚠️  Registry health check timed out after 30s. Check logs: journalctl -u ${REGISTRY_NAME}"
    fi
    sleep 1
done

echo "Waiting for registry Web UI to become healthy..."
for i in $(seq 1 30); do
    if curl -sf "${REGISTRY_UI_URL}/" > /dev/null 2>&1; then
        echo "✅ Registry Web UI is healthy!"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "⚠️  Registry Web UI health check timed out after 30s. Check logs: journalctl -u ${REGISTRY_UI_NAME}"
    fi
    sleep 1
done

# ──────────────────────────────────────────────
# 9. Summary
# ──────────────────────────────────────────────
echo ""
echo "✅ Local Docker Registry + Web UI installed successfully."
echo ""
echo "📊 Service info:"
echo "   Registry API: http://${REGISTRY_HOST}"
echo "   Web UI:       ${REGISTRY_UI_URL}"
echo "   API check:    curl http://${REGISTRY_HOST}/v2/"
echo ""
echo "🔧 Management:"
echo "   systemctl status ${REGISTRY_NAME}"
echo "   systemctl status ${REGISTRY_UI_NAME}"
echo "   journalctl -u ${REGISTRY_NAME} -f"
echo "   journalctl -u ${REGISTRY_UI_NAME} -f"
echo "   systemctl restart ${REGISTRY_NAME}"
echo "   systemctl restart ${REGISTRY_UI_NAME}"
echo ""
echo "📁 Data: ${REGISTRY_DATA_DIR}/"
echo ""
echo "📝 This registry is independent of any single project. Any tool on this"
echo "   host (docker push/pull, Skaffold, k3s, etc.) can use it via:"
echo "   ${REGISTRY_HOST}/<image>:<tag>"
echo ""
echo "   For k3s, point it at this registry with a registries.yaml mirror"
echo "   (see app-skeleton/bootstrap-scripts/prod/setup-k3s.sh for an example)."
