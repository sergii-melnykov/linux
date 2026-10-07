# Optional scripts

Not part of `setup.sh`. Run manually when needed.

## CrowdStrike Falcon (`install-falcon.sh`)

Installs the G2i CrowdStrike Falcon sensor from Box shared links, sets CID, enables `falcon-sensor`.

On Fedora (unsupported by CrowdStrike’s official matrix), the script unpacks the Debian `.deb` into `/opt/CrowdStrike`, fixes SELinux labels, and installs the systemd unit — no `alien`/RPM conversion.

```bash
cd linux/fedora/scripts/optional
./install-falcon.sh
```

Environment:

| Variable | Purpose |
|----------|---------|
| `FALCON_CID` | Customer ID (default: G2i CID in script) |
| `VARIANT` | Force package: `ubuntu`, `debian`, `ubuntu-arm`, `debian-arm`, `centos-arm` |
| `FALCON_DOWNLOAD_DIR` | Cache for `.deb`/`.rpm` (default: `./.cache`) |

Repair permissions/SELinux and restart the service:

```bash
./install-falcon.sh --repair
```

Downloads and large artifacts stay in `.cache/` (gitignored).

**Note:** Fedora may still report RFM if the kernel module is unsupported; use a supported OS for full compliance if your employer requires it.

## VirtualBox (`install-virtualbox.sh`)

Installs VirtualBox, builds signed kernel modules via `akmods`, and enrolls a MOK key when Secure Boot is enabled.

```bash
cd linux/fedora/scripts/optional
sudo bash install-virtualbox.sh
```

After reboot: **Enroll MOK** in the boot menu and enter the password you set during `mokutil --import`.

## Ollama (`install-ollama.sh`)

Installs [Ollama](https://ollama.com) via the upstream install script (systemd service + CLI).

```bash
cd linux/fedora/scripts/optional
sudo bash install-ollama.sh
```
