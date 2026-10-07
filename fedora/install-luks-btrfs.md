# Fedora fresh install (LUKS + Btrfs subvolumes)

Checklist for reinstalling OS with encryption.


## Installer

1. UEFI → USB → **Install to Hard Drive**
2. **Installation Destination** → select **only** Kingston / **nvme0n1**
3. Uncheck **nvme1n1** (Windows) if shown
4. **Storage** → **Automatic** (not Custom / Blivet-GUI) + **Encrypt my data** (TPM optional; keep a passphrase anyway)
5. Anaconda creates: EFI + ext4 **`/boot`** (unencrypted) + **LUKS** with one **Btrfs** pool and subvolumes **`root`** → `/`, **`home`** → `/home` (shared space, not separate partition sizes)
6. Preview: Btrfs + LUKS on nvme0n1 only; no changes to Windows → **Begin Installation**
7. Create user (same username helps restore), reboot, LUKS passphrase at first boot

## After login

```bash
sudo dnf upgrade -y
cd ~/projects/linux/fedora && ./setup.sh
```

Verify:

```bash
lsblk -f
sudo btrfs subvolume list /
```

## Pitfalls

- Losing the LUKS passphrase (no recovery)
- Preview shows LVM/ext4 instead of Btrfs → back to **Automatic** on nvme0n1

See [README.md](./README.md) for post-install tooling.
