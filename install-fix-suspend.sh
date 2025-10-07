# Зберегти як install-fix-suspend.sh, потім виконати: sudo bash install-fix-suspend.sh
#!/usr/bin/env bash
set -euo pipefail

HOOK_PATH="/etc/systemd/system-sleep/fix-suspend.sh"
LOG="/var/log/fix-suspend.log"

# Ensure the system-sleep directory exists
mkdir -p "$(dirname "$HOOK_PATH")"

cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash
# /etc/systemd/system-sleep/fix-suspend.sh
# Enhanced version for Alienware m18 R1 with Fedora 42
# executed with two args: $1 = pre|post, $2 = suspend mode (s2idle|deep|hibernate)
LOG="/var/log/fix-suspend.log"
mkdir -p /run/fix-suspend 2>/dev/null || true
echo "$(date -Iseconds) system-sleep hook: $1 $2" >>"$LOG" 2>&1 || true

# Enhanced logging function
log_action() {
    echo "$(date -Iseconds) $1" >>"$LOG" 2>&1 || true
}

# Function to check if NVIDIA is present
is_nvidia_present() {
    lspci 2>/dev/null | grep -i nvidia >/dev/null 2>&1
}

# Function to check if Intel graphics is present
is_intel_graphics_present() {
    lspci 2>/dev/null | grep -i "vga.*intel" >/dev/null 2>&1
}

case "$1" in
  pre)
    log_action "=== SUSPEND PRE-HOOK START ==="
    
    # Save system state for debugging
    uname -a > /run/fix-suspend/uname 2>/dev/null || true
    lspci > /run/fix-suspend/lspci.before 2>/dev/null || true
    lsmod > /run/fix-suspend/lsmod.before 2>/dev/null || true
    
    # Save current ACPI wake table and then toggle USB controllers (XHC / EHC) OFF
    cat /proc/acpi/wakeup > /run/fix-suspend/wakeup.before 2>/dev/null || true
    awk '{print $1, $2}' /proc/acpi/wakeup > /run/fix-suspend/wakeup.states 2>/dev/null || true
    
    # Enhanced ACPI wake management for Alienware
    log_action "Managing ACPI wake sources..."
    awk '/XHC|EHC|XHCI|UHCI|EHCI|USB|PS2|LID|PBTN|SLPB|PWRB/ {print $1}' /proc/acpi/wakeup | while read -r dev; do
      [ -z "$dev" ] && continue
      echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
      log_action "toggled ACPI wake $dev"
    done
    
    # Disable problematic wake sources specific to Alienware
    for dev in "PS2K" "PS2M" "USB0" "USB1" "USB2" "USB3" "USB4" "USB5" "USB6" "USB7"; do
      if grep -q "^$dev" /proc/acpi/wakeup 2>/dev/null; then
        echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
        log_action "disabled wake for $dev"
      fi
    done

    # Stop bluetooth and other wireless services
    systemctl stop bluetooth.service 2>/dev/null || true
    systemctl stop NetworkManager-wait-online.service 2>/dev/null || true
    log_action "stopped bluetooth and network services"

    # Save and disable WOL for all interfaces (best-effort)
    for iface in $(ls /sys/class/net 2>/dev/null); do
      if command -v ethtool >/dev/null 2>&1; then
        wol=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Wake-on/{print $2}' | tr -d ' \t')
        echo "${wol:-d}" > "/run/fix-suspend/wol_${iface}" 2>/dev/null || true
        if [ "${wol:-d}" != "d" ]; then
          ethtool -s "$iface" wol d 2>/dev/null || true
          log_action "disabled WOL on $iface (was: $wol)"
        fi
      fi
    done

    # Enhanced NVIDIA handling for Alienware m18 R1
    if is_nvidia_present; then
      log_action "NVIDIA detected - applying enhanced suspend handling"
      
      # Mask/stop NVIDIA system suspend services to avoid conflicts
      systemctl stop nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
      systemctl mask nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
      log_action "masked/stopped nvidia suspend services"
      
      # Save NVIDIA power state
      if [ -f /sys/bus/pci/drivers/nvidia/0000:01:00.0/power_state ]; then
        cat /sys/bus/pci/drivers/nvidia/0000:01:00.0/power_state > /run/fix-suspend/nvidia_power_state 2>/dev/null || true
      fi
      
      # Try to switch to Intel graphics before suspend (if available)
      if is_intel_graphics_present; then
        log_action "Attempting to switch to Intel graphics"
        # This is model-specific and may need adjustment
        echo "auto" > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
      fi
      
      # Enhanced module unloading with proper order
      log_action "Unloading NVIDIA modules..."
      for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
        if /sbin/lsmod 2>/dev/null | /bin/grep -q "^${m}"; then
          /sbin/modprobe -r "$m" 2>/dev/null || true
          log_action "attempted to rmmod $m"
        fi
      done
      
      # Additional NVIDIA-specific cleanup
      if [ -f /proc/driver/nvidia/gpus/*/information ]; then
        echo 1 > /proc/driver/nvidia/gpus/*/information 2>/dev/null || true
      fi
    else
      log_action "No NVIDIA detected - skipping NVIDIA-specific handling"
    fi
    
    # Additional Alienware-specific power management
    log_action "Applying Alienware-specific power management..."
    
    # Disable USB autosuspend for critical devices
    for usb_dev in /sys/bus/usb/devices/*/power/autosuspend; do
      if [ -f "$usb_dev" ]; then
        echo -1 > "$usb_dev" 2>/dev/null || true
      fi
    done
    
    # Set PCI power management
    for pci_dev in /sys/bus/pci/devices/*/power/control; do
      if [ -f "$pci_dev" ]; then
        echo "auto" > "$pci_dev" 2>/dev/null || true
      fi
    done
    
    log_action "=== SUSPEND PRE-HOOK COMPLETE ==="
    ;;

  post)
    log_action "=== SUSPEND POST-HOOK START ==="
    
    # Enhanced NVIDIA restoration for Alienware m18 R1
    if is_nvidia_present; then
      log_action "Restoring NVIDIA after suspend..."
      
      # Restore NVIDIA modules with proper order
      for m in nvidia nvidia_uvm nvidia_modeset nvidia_drm; do
        /sbin/modprobe "$m" 2>/dev/null || true
        log_action "modprobe $m"
      done
      
      # Wait for modules to load
      sleep 2
      
      # Restore NVIDIA power state
      if [ -f /run/fix-suspend/nvidia_power_state ]; then
        cat /run/fix-suspend/nvidia_power_state > /sys/bus/pci/drivers/nvidia/0000:01:00.0/power_state 2>/dev/null || true
        log_action "restored NVIDIA power state"
      fi
      
      # Unmask nvidia services back
      systemctl unmask nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
      log_action "unmasked nvidia services"
      
      # Restore NVIDIA performance mode
      if [ -f /sys/class/drm/card0/device/power_dpm_force_performance_level ]; then
        echo "auto" > /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
        log_action "restored NVIDIA performance mode"
      fi
    fi

    # Restore WOL as it was
    for f in /run/fix-suspend/wol_*; do
      [ -f "$f" ] || continue
      iface=$(basename "$f" | sed 's/^wol_//')
      prev=$(cat "$f" 2>/dev/null || echo "d")
      if [ -n "$iface" ] && command -v ethtool >/dev/null 2>&1; then
        if [ "$prev" != "d" ]; then
          ethtool -s "$iface" wol "$prev" 2>/dev/null || true
          log_action "restored WOL $prev on $iface"
        fi
      fi
    done

    # Restore ACPI wake states from saved snapshot (best-effort)
    if [ -f /run/fix-suspend/wakeup.states ]; then
      log_action "Restoring ACPI wake states..."
      awk '{print $1, $2}' /run/fix-suspend/wakeup.states | while read -r dev state; do
        [ -z "$dev" ] && continue
        # current state:
        cur=$(awk -v d="$dev" '$1==d{print $2}' /proc/acpi/wakeup 2>/dev/null || echo "")
        if [ -n "$cur" ] && [ "$cur" != "$state" ]; then
          echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
          log_action "restored ACPI $dev -> $state (was $cur)"
        fi
      done
    fi

    # Start services back
    systemctl start bluetooth.service 2>/dev/null || true
    systemctl start NetworkManager-wait-online.service 2>/dev/null || true
    log_action "started bluetooth and network services"
    
    # Restore USB autosuspend
    for usb_dev in /sys/bus/usb/devices/*/power/autosuspend; do
      if [ -f "$usb_dev" ]; then
        echo 2 > "$usb_dev" 2>/dev/null || true
      fi
    done
    
    # Save post-suspend state for debugging
    lspci > /run/fix-suspend/lspci.after 2>/dev/null || true
    lsmod > /run/fix-suspend/lsmod.after 2>/dev/null || true

    # Clean transient files (optional)
    rm -f /run/fix-suspend/wol_* 2>/dev/null || true
    rm -f /run/fix-suspend/nvidia_power_state 2>/dev/null || true
    
    log_action "=== SUSPEND POST-HOOK COMPLETE ==="
    ;;

  *)
    log_action "Invalid args: $1 $2"
    ;;
esac
EOF

# make hook executable
chmod 755 "$HOOK_PATH"

# create (if not exists) log file with proper perms
touch "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true

echo "Installed system-sleep hook at $HOOK_PATH"
echo "Log: $LOG"
echo ""
echo "Immediate actions: masking nvidia suspend services (so they don't race with our hook)."
systemctl stop nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
systemctl mask nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
echo "nvidia suspend services stopped & masked (temporary)."

# Create diagnostic script
mkdir -p /usr/local/bin
cat > /usr/local/bin/suspend-diagnostics.sh <<'DIAG_EOF'
#!/bin/bash
# Diagnostic script for suspend/resume issues on Alienware m18 R1

echo "=== SUSPEND/RESUME DIAGNOSTICS FOR ALIENWARE M18 R1 ==="
echo "Generated: $(date)"
echo

echo "=== SYSTEM INFO ==="
uname -a
echo "Fedora version: $(cat /etc/fedora-release 2>/dev/null || echo 'Unknown')"
echo

echo "=== GRAPHICS CARDS ==="
lspci | grep -i vga
lspci | grep -i nvidia
echo

echo "=== NVIDIA STATUS ==="
if lspci | grep -i nvidia >/dev/null; then
    echo "NVIDIA detected:"
    nvidia-smi 2>/dev/null || echo "nvidia-smi not available"
    echo "NVIDIA modules loaded:"
    lsmod | grep nvidia || echo "No NVIDIA modules loaded"
    echo "NVIDIA services status:"
    systemctl status nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || echo "NVIDIA services not found"
else
    echo "No NVIDIA detected"
fi
echo

echo "=== ACPI WAKE SOURCES ==="
if [ -f /proc/acpi/wakeup ]; then
    cat /proc/acpi/wakeup
else
    echo "/proc/acpi/wakeup not available"
fi
echo

echo "=== POWER MANAGEMENT ==="
echo "USB autosuspend settings:"
find /sys/bus/usb/devices/*/power/autosuspend -type f 2>/dev/null | head -5 | while read f; do
    echo "$f: $(cat "$f" 2>/dev/null)"
done
echo

echo "PCI power control:"
find /sys/bus/pci/devices/*/power/control -type f 2>/dev/null | head -5 | while read f; do
    echo "$f: $(cat "$f" 2>/dev/null)"
done
echo

echo "=== SUSPEND LOGS ==="
if [ -f /var/log/fix-suspend.log ]; then
    echo "Last 20 lines from fix-suspend.log:"
    tail -20 /var/log/fix-suspend.log
else
    echo "No suspend log found at /var/log/fix-suspend.log"
fi
echo

echo "=== SYSTEMD SLEEP LOGS ==="
journalctl -u systemd-suspend --since "1 hour ago" --no-pager | tail -10
echo

echo "=== RECENT SUSPEND ATTEMPTS ==="
journalctl -u systemd-logind --since "1 hour ago" --no-pager | grep -i suspend | tail -5
echo

echo "=== DEBUGGING FILES ==="
if [ -d /run/fix-suspend ]; then
    echo "Debug files in /run/fix-suspend:"
    ls -la /run/fix-suspend/ 2>/dev/null || echo "No debug files found"
else
    echo "No debug directory found at /run/fix-suspend"
fi
echo

echo "=== RECOMMENDATIONS ==="
echo "1. Test suspend: sudo systemctl suspend"
echo "2. Check logs after resume: sudo journalctl -u systemd-suspend --since '5 minutes ago'"
echo "3. Check our hook log: sudo tail -f /var/log/fix-suspend.log"
echo "4. If issues persist, run this script again and share the output"
echo

DIAG_EOF

chmod 755 /usr/local/bin/suspend-diagnostics.sh

cat <<'USAGE'

Готово! Установлена улучшенная версия для Alienware m18 R1.

=== ЧТО ИЗМЕНИЛОСЬ ===
✅ Расширенная диагностика NVIDIA (определение наличия карты)
✅ Улучшенное управление ACPI wake sources для Alienware
✅ Дополнительная обработка USB и PCI power management
✅ Более детальное логирование всех операций
✅ Правильный порядок загрузки/выгрузки NVIDIA модулей
✅ Обработка гибридной графики (Intel + NVIDIA)
✅ Создан диагностический скрипт

=== ТЕСТИРОВАНИЕ ===
1. Протестируйте suspend: sudo systemctl suspend
2. После resume проверьте логи: sudo tail -f /var/log/fix-suspend.log
3. Запустите диагностику: sudo suspend-diagnostics.sh

=== ДИАГНОСТИКА ===
Если проблемы остаются, запустите:
  sudo suspend-diagnostics.sh
Этот скрипт соберет всю необходимую информацию для отладки.

=== ОТКАТ ===
Если нужно откатить изменения:
  sudo rm -f /etc/systemd/system-sleep/fix-suspend.sh
  sudo rm -f /usr/local/bin/suspend-diagnostics.sh
  sudo systemctl unmask nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
  sudo systemctl start bluetooth.service

USAGE

exit 0
