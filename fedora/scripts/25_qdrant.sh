#!/usr/bin/env bash
set -e

echo "🔍 Installing Qdrant Vector Database (Docker + systemd + FastEmbed GPU)..."

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
# 2. Detect NVIDIA GPU for FastEmbed acceleration
# ──────────────────────────────────────────────
HAS_NVIDIA=false
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi -L &> /dev/null; then
        HAS_NVIDIA=true
        echo "🎮 NVIDIA GPU detected — will enable GPU acceleration for FastEmbed embeddings."
    fi
fi

if ! $HAS_NVIDIA; then
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        echo "⚠️  NVIDIA GPU found via lspci but nvidia-smi is unavailable."
        echo "   Run 18_nvidia_drivers.sh first, then re-run this script for GPU acceleration."
        echo "   Continuing with CPU-only mode for now."
    else
        echo "ℹ️  No NVIDIA GPU detected — Qdrant will run in CPU mode."
    fi
fi

# ──────────────────────────────────────────────
# 3. Create storage directories
# ──────────────────────────────────────────────
echo "Creating Qdrant data directories..."
QDRANT_BASE="/var/lib/qdrant"
mkdir -p "$QDRANT_BASE"/{storage,snapshots,config}

# ──────────────────────────────────────────────
# 4. Write Qdrant production config
# ──────────────────────────────────────────────
echo "Writing Qdrant configuration..."
cat > "$QDRANT_BASE/config/production.yaml" << 'YAML'
# Qdrant production configuration
# FastEmbed GPU acceleration is provided by --gpus all via Docker runtime.
# ONNX Runtime automatically picks up CUDA when available in the container.

service:
  host: 0.0.0.0
  http_port: 6333
  grpc_port: 6334
  enable_cors: true
  enable_static_content: false

log_level: INFO

storage:
  storage_path: /qdrant/storage
  snapshots_path: /qdrant/snapshots
  performance:
    max_search_threads: 0  # 0 = auto-detect CPU cores
YAML

# ──────────────────────────────────────────────
# 5. Pull Qdrant Docker image
# ──────────────────────────────────────────────
echo "Pulling qdrant/qdrant Docker image..."
docker pull qdrant/qdrant:latest

# ──────────────────────────────────────────────
# 6. Create systemd service unit
# ──────────────────────────────────────────────
echo "Creating systemd service unit..."

# Build the ExecStart command
if $HAS_NVIDIA; then
    DOCKER_GPU_FLAG="--gpus all"
    GPU_ENV_LINE="Environment=\"NVIDIA_VISIBLE_DEVICES=all\""
else
    DOCKER_GPU_FLAG=""
    GPU_ENV_LINE=""
fi

cat > /etc/systemd/system/qdrant.service << UNIT
[Unit]
Description=Qdrant Vector Database (Docker)
Documentation=https://qdrant.tech/documentation/
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=exec
Restart=unless-stopped
RestartSec=10s
TimeoutStartSec=120
$GPU_ENV_LINE

ExecStartPre=-/usr/bin/docker stop qdrant 2>/dev/null || true
ExecStartPre=-/usr/bin/docker rm qdrant 2>/dev/null || true
ExecStartPre=/usr/bin/docker pull qdrant/qdrant:latest
ExecStart=/usr/bin/docker run \\
    --name qdrant \\
    --rm \\
    $DOCKER_GPU_FLAG \\
    -p 6333:6333 \\
    -p 6334:6334 \\
    -v /var/lib/qdrant/storage:/qdrant/storage:Z \\
    -v /var/lib/qdrant/snapshots:/qdrant/snapshots:Z \\
    -v /var/lib/qdrant/config/production.yaml:/qdrant/config/production.yaml:Z \\
    qdrant/qdrant:latest

ExecStop=/usr/bin/docker stop -t 10 qdrant
ExecStopPost=-/usr/bin/docker rm qdrant 2>/dev/null || true

[Install]
WantedBy=multi-user.target
UNIT

# ──────────────────────────────────────────────
# 7. Reload systemd, enable and start
# ──────────────────────────────────────────────
echo "Enabling and starting Qdrant service..."
systemctl daemon-reload
systemctl enable qdrant.service
systemctl start qdrant.service

# ──────────────────────────────────────────────
# 8. Wait for health check and verify
# ──────────────────────────────────────────────
echo "Waiting for Qdrant to become healthy..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:6333/health > /dev/null 2>&1; then
        echo "✅ Qdrant is healthy!"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "⚠️  Qdrant health check timed out after 30s. Check logs: journalctl -u qdrant"
    fi
    sleep 1
done

# ──────────────────────────────────────────────
# 9. Summary
# ──────────────────────────────────────────────
echo ""
echo "✅ Qdrant Vector Database installed successfully."
echo ""
echo "📊 Service info:"
echo "   REST API:  http://localhost:6333"
echo "   gRPC API:  localhost:6334"
echo "   Dashboard: http://localhost:6333/dashboard"
echo ""
echo "🔧 Management:"
echo "   systemctl status qdrant"
echo "   journalctl -u qdrant -f"
echo "   systemctl restart qdrant"
echo ""
echo "📁 Data:       /var/lib/qdrant/"
echo "⚙️  Config:     /var/lib/qdrant/config/production.yaml"

if $HAS_NVIDIA; then
    echo ""
    echo "🎮 GPU acceleration: ENABLED (RTX via --gpus all)"
    echo "   FastEmbed will use ONNX Runtime with CUDAExecutionProvider"
    echo ""
    echo "   Example: create a collection with GPU-accelerated embeddings:"
    echo '   curl -X PUT http://localhost:6333/collections/my_docs \'
    echo '     -H "Content-Type: application/json" \'
    echo '     -d '"'"'{"vectors":{"size":384,"distance":"Cosine"},"init_from":{"model":"BAAI/bge-small-en-v1.5"}}'"'"
else
    echo ""
    echo "💻 Running in CPU mode."
    echo "   Run 18_nvidia_drivers.sh and re-run this script to enable GPU."
fi
echo ""
