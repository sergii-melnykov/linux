#!/usr/bin/env bash
# Sync Kiro IDE from the official tarball CDN into a local DNF repository.
set -euo pipefail

METADATA_URL="https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-stable.json"
REPO_DIR="/var/lib/kiro-rpm-repo"
BUILD_DIR="/var/tmp/kiro-build"
STAGING_DIR="${BUILD_DIR}/staging"
KIRO_USER_AGENT="Electron"

log() {
    echo "[kiro-repo-sync] $*"
}

cleanup_build() {
    rm -rf "${BUILD_DIR}/extract" "${STAGING_DIR}"
}

fetch_metadata() {
    local metadata_file="${BUILD_DIR}/metadata.json"
    mkdir -p "$BUILD_DIR"
    curl -fsSL -A "$KIRO_USER_AGENT" "$METADATA_URL" -o "$metadata_file"
    TARGET_VERSION="$(jq -r '.currentRelease' "$metadata_file")"
    TARBALL_URL="$(jq -r '.releases[] | select(.updateTo.url | endswith(".tar.gz")) | .updateTo.url' "$metadata_file" | head -1)"

    if [[ -z "$TARGET_VERSION" || "$TARGET_VERSION" == "null" ]]; then
        log "ERROR: Could not determine current release from metadata."
        exit 1
    fi
    if [[ -z "$TARBALL_URL" || "$TARBALL_URL" == "null" ]]; then
        log "ERROR: Could not determine tarball URL from metadata."
        exit 1
    fi
}

repo_has_version() {
    local version="$1"
    compgen -G "${REPO_DIR}/kiro-${version}-*.rpm" > /dev/null
}

prepare_staging() {
    local extract_dir="${BUILD_DIR}/extract"
    local tarball="${BUILD_DIR}/kiro.tar.gz"
    local kiro_dir

    rm -rf "$extract_dir" "$STAGING_DIR"
    mkdir -p "$extract_dir" "${STAGING_DIR}/opt"

    log "Downloading Kiro ${TARGET_VERSION}..."
    curl -fsSL -A "$KIRO_USER_AGENT" "$TARBALL_URL" -o "$tarball"
    tar -xzf "$tarball" -C "$extract_dir"

    kiro_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -d "${extract_dir}/Kiro" ]]; then
        kiro_dir="${extract_dir}/Kiro"
    elif [[ -d "${kiro_dir}/Kiro" ]]; then
        kiro_dir="${kiro_dir}/Kiro"
    fi

    if [[ ! -d "$kiro_dir" ]]; then
        log "ERROR: Could not locate Kiro directory in extracted tarball."
        find "$extract_dir" -maxdepth 3 -type d | head -20
        exit 1
    fi
    if [[ ! -f "${kiro_dir}/bin/kiro" && ! -f "${kiro_dir}/kiro" ]]; then
        log "ERROR: Extracted package is missing the kiro executable."
        exit 1
    fi

    # Move instead of cp -a: node_modules symlinks break recursive copy.
    mv "$kiro_dir" "${STAGING_DIR}/opt/kiro"
    chmod +x "${STAGING_DIR}/opt/kiro/bin/kiro" 2>/dev/null || true
    chmod +x "${STAGING_DIR}/opt/kiro/kiro" 2>/dev/null || true
    if [[ -f "${STAGING_DIR}/opt/kiro/chrome-sandbox" ]]; then
        chmod 4755 "${STAGING_DIR}/opt/kiro/chrome-sandbox"
    fi

    mkdir -p "${STAGING_DIR}/usr/bin"
    ln -sf ../../opt/kiro/bin/kiro "${STAGING_DIR}/usr/bin/kiro"

    local icon_src=""
    if [[ -f "${STAGING_DIR}/opt/kiro/resources/app/resources/linux/kiro.png" ]]; then
        icon_src="${STAGING_DIR}/opt/kiro/resources/app/resources/linux/kiro.png"
    elif [[ -f "${STAGING_DIR}/opt/kiro/resources/app/resources/app.png" ]]; then
        icon_src="${STAGING_DIR}/opt/kiro/resources/app/resources/app.png"
    fi

    mkdir -p "${STAGING_DIR}/usr/share/applications"
    cat > "${STAGING_DIR}/usr/share/applications/kiro.desktop" <<EOF
[Desktop Entry]
Name=Kiro
Comment=Kiro - agentic AI development environment
Exec=/opt/kiro/bin/kiro %U
Icon=kiro
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=text/plain;inode/directory;
StartupWMClass=kiro
StartupNotify=true
EOF

    if [[ -n "$icon_src" ]]; then
        mkdir -p "${STAGING_DIR}/usr/share/icons/hicolor/512x512/apps"
        cp "$icon_src" "${STAGING_DIR}/usr/share/icons/hicolor/512x512/apps/kiro.png"
    fi
}

build_rpm() {
    local rpmtop spec_file rpm_file extra_files=""
    rpmtop="$(mktemp -d /var/tmp/kiro-rpmbuild.XXXXXX)"
    spec_file="${rpmtop}/SPECS/kiro.spec"
    mkdir -p "${rpmtop}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

    if [[ -f "${STAGING_DIR}/usr/share/icons/hicolor/512x512/apps/kiro.png" ]]; then
        extra_files+="/usr/share/icons/hicolor/512x512/apps/kiro.png
"
    fi

    cat > "$spec_file" <<SPEC
Name:           kiro
Version:        ${TARGET_VERSION}
Release:        1%{?dist}
Summary:        Kiro IDE - agentic AI development environment
License:        LicenseRef-Kiro
URL:            https://kiro.dev/
BuildArch:      x86_64
AutoReqProv:    no

%description
Kiro is an agentic IDE that works alongside you from prototype to production.
Packaged from the official Linux tarball for local DNF updates.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -C ${STAGING_DIR} -cf - . | tar -C %{buildroot} -xf -

%files
/opt/kiro
/usr/bin/kiro
/usr/share/applications/kiro.desktop
${extra_files}
%changelog
* $(date +"%a %b %d %Y") Kiro Local Repo <kiro@localhost> - ${TARGET_VERSION}-1
- Sync from official tarball ${TARGET_VERSION}
SPEC

    log "Building RPM for Kiro ${TARGET_VERSION}..."
    rpmbuild -bb --define "_topdir ${rpmtop}" "$spec_file" > /dev/null 2>&1

    rpm_file="$(find "${rpmtop}/RPMS" -name 'kiro-*.rpm' -type f | head -1)"
    if [[ -z "$rpm_file" ]]; then
        log "ERROR: RPM build did not produce an output package."
        rm -rf "$rpmtop"
        exit 1
    fi

    mkdir -p "$REPO_DIR"
    find "$REPO_DIR" -maxdepth 1 -name 'kiro-*.rpm' -delete
    cp "$rpm_file" "$REPO_DIR/"
    rm -rf "$rpmtop"
    log "Published $(basename "$rpm_file") to ${REPO_DIR}"
}

refresh_repo_metadata() {
    log "Refreshing repository metadata..."
    createrepo_c --update "$REPO_DIR" > /dev/null
}

main() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "ERROR: This script must be run as root."
        exit 1
    fi

    fetch_metadata

    if repo_has_version "$TARGET_VERSION"; then
        if [[ ! -f "${REPO_DIR}/repodata/repomd.xml" ]]; then
            log "Repository metadata missing; refreshing..."
            refresh_repo_metadata
        else
            log "Repository already contains Kiro ${TARGET_VERSION}; nothing to do."
        fi
        exit 0
    fi

    log "Building Kiro ${TARGET_VERSION} for local DNF repository..."
    prepare_staging
    build_rpm
    refresh_repo_metadata
    cleanup_build
    log "Done. Upgrade with: dnf update kiro"
}

main "$@"
