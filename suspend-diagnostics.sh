#!/usr/bin/env bash
# suspend-diagnostics.sh
# Збирає логи й діагностичні дані для аналізу проблем зі сном/пробудження (suspend/resume)
# Використання: sudo bash suspend-diagnostics.sh
# Вихід: архів /tmp/suspend-diagnostics-<TIMESTAMP>.tar.gz

set -euo pipefail
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
outdir="/tmp/suspend-diagnostics-$timestamp"
archive="/tmp/suspend-diagnostics-$timestamp.tar.gz"
mkdir -p "$outdir"

echo "Collecting system info into $outdir"

# Basic system info
uname -a > "$outdir/uname.txt" 2>&1 || true
cat /proc/cmdline > "$outdir/proc_cmdline.txt" 2>&1 || true
cat /sys/power/state > "$outdir/sys_power_state.txt" 2>&1 || true
cat /sys/power/mem_sleep > "$outdir/sys_power_mem_sleep.txt" 2>&1 || true

# ACPI wake devices
cat /proc/acpi/wakeup > "$outdir/proc_acpi_wakeup.txt" 2>&1 || true

# Kernel boot/journal logs (previous boot where suspend likely happened)
# previous boot (-b -1) and recent kernel logs
journalctl -k -b -1 -o short-iso > "$outdir/journalctl_k_prevboot.txt" 2>&1 || true
journalctl -k --since "2 hours ago" -o short-iso > "$outdir/journalctl_k_2h.txt" 2>&1 || true

# Filtered suspend/resume related kernel messages
journalctl -k -b -1 -o short-iso | egrep -i 'suspend|resume|s2idle|S3|PM: suspend|nvidia|drm|EDID' > "$outdir/journal_suspend_prevboot.txt" 2>&1 || true
journalctl -k --since "2 hours ago" | egrep -i 'suspend|resume|s2idle|S3|PM: suspend|nvidia|drm|EDID' > "$outdir/journal_suspend_recent.txt" 2>&1 || true

# systemd services related to nvidia and sleep
systemctl status nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service > "$outdir/nvidia_suspend_status.txt" 2>&1 || true
journalctl -u nvidia-suspend.service -b -1 > "$outdir/journal_nvidia_suspend_prevboot.txt" 2>&1 || true
journalctl -u nvidia-resume.service -b -1 > "$outdir/journal_nvidia_resume_prevboot.txt" 2>&1 || true

# dmesg (timestamped)
dmesg -T > "$outdir/dmesg_T.txt" 2>&1 || true

# Hardware & drivers
lsmod > "$outdir/lsmod.txt" 2>&1 || true
lspci -k > "$outdir/lspci_k.txt" 2>&1 || true

# BIOS / firmware info
which dmidecode >/dev/null 2>&1 && dmidecode -s bios-version > "$outdir/bios_version.txt" 2>&1 || true
which dmidecode >/dev/null 2>&1 && dmidecode -s bios-release-date > "$outdir/bios_release_date.txt" 2>&1 || true

# Network / BT (may help identify wake sources)
ip link show > "$outdir/ip_link.txt" 2>&1 || true
which ethtool >/dev/null 2>&1 && for iface in $(ls /sys/class/net); do ethtool "$iface" 2>&1 | sed -n '1,120p' > "$outdir/ethtool_${iface}.txt" 2>&1 || true; done || true
systemctl status bluetooth > "$outdir/bluetooth_status.txt" 2>&1 || true

# Useful user-space state
ps -e -o pid,comm > "$outdir/ps_comm.txt" 2>&1 || true
systemctl list-units --type=service --state=failed > "$outdir/systemd_failed_services.txt" 2>&1 || true

# Save a copy of relevant config files (if present)
[ -f /etc/default/grub ] && cp /etc/default/grub "$outdir/" || true
[ -f /etc/modprobe.d/nvidia.conf ] && cp /etc/modprobe.d/nvidia.conf "$outdir/" || true

# Limit size of collected logs (optional): gzip large text files to save space
find "$outdir" -type f -name '*.txt' -size +200k -exec gzip -9 {} \; || true

# Create archive
tar -czf "$archive" -C /tmp "$(basename "$outdir")"
chmod 600 "$archive" || true

echo "Done. Archive created: $archive"

echo "Files collected (top-level):"
ls -1 "$outdir" | sed -n '1,200p' || true

echo "If you want, attach the archive or paste selected files (e.g. journal_suspend_prevboot.txt and proc_acpi_wakeup.txt)."
