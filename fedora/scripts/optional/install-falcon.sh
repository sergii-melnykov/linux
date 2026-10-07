#!/usr/bin/env bash
# CrowdStrike Falcon sensor install helper (G2i Box shares + CID)
set -euo pipefail

CID="${FALCON_CID:-73AE1FF8DAE24CB7A0CD48DCE1FA3FF4-6A}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${FALCON_DOWNLOAD_DIR:-${SCRIPT_DIR}/.cache}"
OS_ID="$(. /etc/os-release && echo "${ID:-unknown}")"

mkdir -p "$CACHE_DIR"

is_rpm_os() {
  case "$OS_ID" in
    fedora|rhel|centos|rocky|almalinux|ol|mageia|openmandriva|suse|opensuse*) return 0 ;;
    *) return 1 ;;
  esac
}

declare -A PACKAGES=(
  [ubuntu]="sctgxk2r0lvrncrdvff0b47m0flfbcdw|falcon ubuntu.deb|2186829021385"
  [ubuntu-arm]="80h4494xvzcjwppyogfpjnccf1pwv4h0|falcon ubuntu arm.deb|2186819514205"
  [debian]="mmjvmozk9bg4ku66wzz87ocw522imgvf|falcon debian.deb|2186817279949"
  [debian-arm]="jl3rl36meqmwopxns2twfddrcojr3lfe|falcon debian arm.deb|2186832308507"
  [centos-arm]="salt8g7b50h1lpq2ut7deyms5b30s0ss|centos arm.rpm|2186831212376"
)

download_box_shared() {
  local shared_name="$1"
  local out_file="$2"
  local file_id="${3:-}"

  if [[ -n "$file_id" && "$file_id" != f_* ]]; then
    file_id="f_${file_id}"
  fi

  local url
  if [[ -n "$file_id" ]]; then
    url="https://g2i.box.com/index.php?rm=box_download_shared_file&shared_name=${shared_name}&file_id=${file_id}"
  else
    echo "Need file_id for ${shared_name}; open share page and grep itemID in HTML." >&2
    return 1
  fi

  echo "Downloading ${out_file} ..."
  curl -fsSL -o "${CACHE_DIR}/${out_file}" "$url"
}

pick_variant() {
  local arch os_id
  arch="$(uname -m)"
  os_id="$(. /etc/os-release && echo "${ID:-unknown}")"

  case "${arch}:${os_id}" in
    x86_64:ubuntu) echo ubuntu ;;
    aarch64:ubuntu|arm64:ubuntu) echo ubuntu-arm ;;
    x86_64:debian) echo debian ;;
    aarch64:debian|arm64:debian) echo debian-arm ;;
    aarch64:fedora|aarch64:rhel|aarch64:centos|aarch64:rocky|aarch64:almalinux|arm64:*)
      echo centos-arm
      ;;
    x86_64:fedora|x86_64:rhel|x86_64:centos|x86_64:rocky|x86_64:almalinux)
      echo debian
      echo "Note: no x86 RPM in provided links; using Debian .deb with manual install on RPM distros." >&2
      ;;
    *)
      echo "Could not auto-select package for ${arch} on ${os_id}. Set VARIANT=ubuntu|debian|..." >&2
      exit 1
      ;;
  esac
}

VARIANT="${VARIANT:-$(pick_variant)}"
IFS='|' read -r shared_name filename file_id <<< "${PACKAGES[$VARIANT]}"

if [[ ! -f "${CACHE_DIR}/${filename}" ]]; then
  download_box_shared "$shared_name" "$filename" "$file_id"
fi

finalize_falcon_payload_permissions() {
  echo "Fixing ownership, modes, and SELinux labels under /opt/CrowdStrike ..."
  sudo chown -R root:root /opt/CrowdStrike
  sudo find /opt/CrowdStrike -type d -exec chmod 755 {} +
  sudo find /opt/CrowdStrike -type f -exec chmod 644 {} +
  while IFS= read -r -d '' f; do
    sudo chmod 750 "$f"
  done < <(find /opt/CrowdStrike -type f \( -name '*18803' -o -name 'falconctl' -o -name 'falcond' -o -name 'falcon-sensor' \) ! -type l -print0 2>/dev/null)

  if command -v getenforce >/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
    if command -v semanage >/dev/null; then
      sudo semanage fcontext -a -t bin_t '/opt/CrowdStrike(/.*)?' 2>/dev/null \
        || sudo semanage fcontext -m -t bin_t '/opt/CrowdStrike(/.*)?' 2>/dev/null \
        || true
    fi
    if sudo chcon -R -t bin_t /opt/CrowdStrike 2>/dev/null; then
      :
    else
      sudo restorecon -Rv /opt/CrowdStrike 2>/dev/null || true
    fi
  fi
}

ensure_prerequisites() {
  if [[ "$filename" != *.deb ]]; then
    return 0
  fi

  if is_rpm_os; then
    if ! command -v ar >/dev/null || ! tar --help 2>&1 | grep -q xz; then
      echo "Installing binutils (ar) for .deb extraction ..."
      sudo dnf install -y binutils tar xz
    fi
    return 0
  fi

  if ! command -v dpkg >/dev/null; then
    case "$OS_ID" in
      debian|ubuntu|linuxmint|pop)
        echo "Installing dpkg ..."
        sudo apt-get update
        sudo apt-get install -y dpkg
        ;;
      *)
        cat >&2 <<EOF
Missing installer tools for .deb on ${OS_ID}.

Fedora/RHEL:  sudo dnf install -y binutils tar xz
Debian/Ubuntu: sudo apt-get install -y dpkg
EOF
        exit 1
        ;;
    esac
  fi
}

install_deb_on_rpm_os() {
  local pkg="$1"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/falcon-deb.XXXXXX")"

  echo "Installing $(basename "$pkg") from .deb payload (avoids alien/RPM path conflicts on ${OS_ID}) ..."
  (
    cd "$tmp"
    ar x "$pkg"
    tar -xJf data.tar.xz
  )

  if [[ -L /opt/CrowdStrike ]]; then
    echo "Refusing to install: /opt/CrowdStrike is a symlink (see package preinst)." >&2
    rm -rf "$tmp"
    exit 1
  fi

  sudo install -d -m 755 /opt/CrowdStrike
  sudo cp -a "${tmp}/opt/CrowdStrike/." /opt/CrowdStrike/
  finalize_falcon_payload_permissions

  if [[ -f "${tmp}/etc/logrotate.d/falcon-sensor" ]]; then
    sudo install -D -m 644 "${tmp}/etc/logrotate.d/falcon-sensor" /etc/logrotate.d/falcon-sensor
  fi

  if [[ -f "${tmp}/lib/systemd/system/falcon-sensor.service" ]]; then
    sudo install -D -m 644 "${tmp}/lib/systemd/system/falcon-sensor.service" \
      /usr/lib/systemd/system/falcon-sensor.service
    sudo systemctl daemon-reload
  fi

  rm -rf "$tmp"
}

install_pkg() {
  local pkg="${CACHE_DIR}/${filename}"
  if [[ "$filename" == *.deb ]]; then
    if is_rpm_os; then
      install_deb_on_rpm_os "$pkg"
    elif command -v dpkg >/dev/null; then
      sudo dpkg -i "$pkg" || sudo apt-get install -f -y
    else
      echo "Install dpkg (Debian/Ubuntu) or use this script on Fedora/RHEL." >&2
      exit 1
    fi
  elif [[ "$filename" == *.rpm ]]; then
    sudo rpm -ivh "$pkg"
  fi
}

if [[ "${1:-}" == "--repair" ]]; then
  finalize_falcon_payload_permissions
  sudo systemctl daemon-reload
  echo "Restarting falcon-sensor ..."
  sudo systemctl restart falcon-sensor
  sudo /opt/CrowdStrike/falconctl -g --cid || true
  systemctl status falcon-sensor --no-pager || true
  exit 0
fi

ensure_prerequisites

install_pkg

echo "Setting CID and starting falcon-sensor ..."
sudo /opt/CrowdStrike/falconctl -s --cid="${CID}" -f
sudo systemctl enable --now falcon-sensor
sudo /opt/CrowdStrike/falconctl -g --cid
systemctl status falcon-sensor --no-pager || true
