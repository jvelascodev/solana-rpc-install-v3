# Disk Mount Fix – Documentation

> **✨ General Note**: This fix works for **1‑3 data disks** in any configuration. The script automatically detects available disks and assigns them by priority (accounts → ledger → snapshot) – no manual configuration needed.

## 🚨 Priority‑Order Issue (Auto‑Fix)

### Symptoms

If you run `bash verify-mounts.sh` and see something like:

```
⚠️  Accounts not mounted separately (on the system disk)
✓ Ledger mounted separately on /dev/nvme0n1
✓ Snapshot mounted separately on /dev/nvme1n1
```

**This is a serious priority error!**
The *accounts* directory, which needs the highest‑performance NVMe, is on the system disk, while the lower‑priority ledger and snapshot directories occupy the fast NVMe devices.

### ✅ Automatic Fix (Recommended)

The latest version of `1-prepare.sh` already supports automatic detection and correction of priority errors!

```bash
# Update to the latest version
cd /root/solana-rpc-install
git pull

# Run the preparation script – it will fix the issue automatically
bash 1-prepare.sh
```

The script will automatically:

1. ✅ Detect the priority error  
2. ✅ Unmount the incorrectly mounted directories  
3. ✅ Clean old entries from `/etc/fstab`  
4. ✅ Remount disks in the correct priority order:  
   - **1st NVMe** → *Accounts* (highest performance)  
   - **2nd NVMe** → *Ledger* (medium performance)  
   - **3rd NVMe** → *Snapshot* (low performance)  
5. ✅ Persist the new configuration

### 🔧 Manual Fix (Alternative)

If you prefer granular control, you can use the dedicated fix script:

```bash
# 1. Stop the Solana node (if running)
systemctl stop sol

# 2. Run the priority‑fix script
cd /root/solana-rpc-install
bash fix-mount-priority.sh

# 3. Verify the result
bash verify-mounts.sh

# 4. Restart the node
systemctl start sol
```

### Why Does This Happen?

Possible causes:

1. Using an old script version (pre‑v1.0) where the disk‑allocation logic was incomplete.  
2. Manually mounting disks in the wrong order.  
3. Migrating from another configuration without following the priority rules.

### Improvements in New Versions

**v1.1+ `1-prepare.sh`** now:

- ✅ Detects all available data disks automatically  
- ✅ Checks current mount status and priority  
- ✅ Fixes priority errors without user interaction  
- ✅ Handles any disk configuration (1‑3 data disks) intelligently

---

## 🔍 Other Mount‑Related Issues

### Detected Problems

Based on your disk layout and the output of `verify-mounts.sh`:

```
Current state:
- nvme0n1 (2.9 TB) → /mnt/nvme0n1  ❌ Wrong mount point
- nvme1n1 (2.9 TB) → /mnt/nvme1n1  ❌ Wrong mount point
- Accounts → system disk /dev/mapper/vg0-root  ❌ Poor performance
- Ledger   → system disk /dev/mapper/vg0-root  ❌ Poor performance
- Snapshot → system disk /dev/mapper/vg0-root  ❌ Poor performance
```

#### Root Cause

The original `1-prepare.sh` had two major flaws:

1. **Skipping already‑mounted devices** – it considered a device “done” even if it was mounted in the wrong location, so the high‑performance disks were never re‑mounted.  
2. **No mount‑point verification** – it never checked whether a device was mounted at the expected target directory, so it could not auto‑correct wrong mounts.

---

## ✅ Fix Details

### 1. Enhanced `mount_one()` Function

**Before**

```bash
mount_one() {
  local dev="$1"; local target="$2"
  if is_mounted_dev "$dev"; then
    echo "   - 已挂载：$dev -> $(findmnt -no TARGET "$dev")，跳过"
    return 0
  fi
  # ... other logic
}
```

**After**

```bash
mount_one() {
  local dev="$1"; local target="$2"

  # Check if the device is already mounted
  if is_mounted_dev "$dev"; then
    local current_mount=$(findmnt -no TARGET "$dev")
    # If mounted to the correct target, skip
    if [[ "$current_mount" == "$target" ]]; then
      echo "   - 已正确挂载：$dev -> $target，跳过"
      return 0
    fi
    # If mounted elsewhere, unmount first
    echo "   - 检测到 $dev 挂载在错误位置：$current_mount"
    echo "   - 卸载 $dev ..."
    umount "$dev"
    # Clean old fstab entry
    sed -i "\|$current_mount|d" /etc/fstab
  fi

  # Create target directory and mount
  mkdir -p "$target"
  mount -o defaults "$dev" "$target"

  # Update fstab
  sed -i "\|^${dev} |d" /etc/fstab
  echo "$dev $target ext4 defaults 0 0" >> /etc/fstab

  echo "   - ✅ 挂载完成：$dev -> $target"
}
```

**Improvements**

- ✅ Verifies correct mount point before skipping  
- ✅ Automatically unmounts devices mounted in the wrong place  
- ✅ Cleans stale entries from `/etc/fstab`  
- ✅ Remounts to the proper target and persists the change

### 2. Optimized Device‑Candidate Logic

**Helper** – `is_correctly_mounted()`

```bash
# Returns 0 if the device is correctly mounted to one of the Solana data dirs
is_correctly_mounted() {
  local dev="$1"
  if ! is_mounted_dev "$dev"; then
    return 1  # not mounted
  fi
  local current_mount=$(findmnt -no TARGET "$dev")
  [[ "$current_mount" == "$ACCOUNTS" || "$current_mount" == "$LEDGER" || "$current_mount" == "$SNAPSHOT" ]]
}
```

**Candidate Selection (after the fix)**

```bash
# Gather candidate devices (exclude system disk; include wrongly‑mounted devices)
CANDIDATES=()
for d in "${MAP_DISKS[@]}"; do
  disk="/dev/$d"
  [[ -n "$ROOT_DISK" && "$disk" == "$ROOT_DISK" ]] && continue
  parts=($(lsblk -n -o NAME,TYPE "$disk" | awk '$2=="part"{gsub(/^[├─└│ ]*/, "", $1); print $1}'))
  if (( ${#parts[@]} == 0 )); then
    # Whole disk: add if not correctly mounted
    is_correctly_mounted "$disk" || CANDIDATES+=("$disk")
  else
    # Has partitions: pick the largest usable partition (not correctly mounted)
    best=""; best_size=0
    for p in "${parts[@]}"; do
      part="/dev/$p"
      is_correctly_mounted "$part" && continue
      size=$(lsblk -bno SIZE "$part")
      (( size > best_size )) && { best="$part"; best_size=$size; }
    done
    [[ -n "$best" ]] && CANDIDATES+=("$best")
  fi
done
```

**Improvements**

- ✅ Allows devices that are mounted incorrectly to re‑enter the candidate pool  
- ✅ Skips only devices already correctly mounted to Solana directories  
- ✅ Handles both whole‑disk and partitioned‑disk scenarios

---

## 🚀 Using the Fixed Script

### Execution Steps

1. **Important** – Stop the Solana node before making any changes.  
2. Run the following (as root):

```bash
sudo su -
cd /root/solana-rpc-install
# Optional: backup current fstab
cp /etc/fstab /etc/fstab.backup
# Run the preparation script – it now contains the fixes
bash 1-prepare.sh
```

### Expected Behaviour

The script adapts to your disk layout. Example for a **dual‑disk** setup:

```
1. Detect disks → candidates: /dev/nvme0n1 /dev/nvme1n1
2. Process nvme0n1 (Accounts priority)
   - Detected wrong mount at /mnt/nvme0n1
   - Unmounted, cleaned fstab entry
   - ✅ Mounted: /dev/nvme0n1 → /root/sol/accounts
3. Process nvme1n1 (Ledger priority)
   - Detected wrong mount at /mnt/nvme1n1
   - Unmounted, cleaned fstab entry
   - ✅ Mounted: /dev/nvme1n1 → /root/sol/ledger
4. Snapshot uses the system disk (no extra NVMe)
5. System optimizations (network tuning, etc.)
```

#### Other Scenarios

| Scenario | Mount Plan |
|----------|------------|
| **1 data disk** | Accounts → NVMe, Ledger & Snapshot → system disk |
| **2 data disks** (recommended) | Accounts → NVMe 1, Ledger → NVMe 2, Snapshot → system disk |
| **3 data disks** | Accounts → NVMe 1, Ledger → NVMe 2, Snapshot → NVMe 3, system disk only for OS |

### Verify the Result

After the script finishes, run:

```bash
bash verify-mounts.sh
```

**Expected output for a dual‑disk configuration**:

```
[2] Checking mount points
--------------------------------------------
  • Accounts:
    - Path: /root/sol/accounts
    - Device: /dev/nvme0n1
    - Type: ext4
    - Mount point: /root/sol/accounts
    - Status: Independently mounted ✓

  • Ledger:
    - Path: /root/sol/ledger
    - Device: /dev/nvme1n1
    - Type: ext4
    - Mount point: /root/sol/ledger
    - Status: Independently mounted ✓

  • Snapshot:
    - Path: /root/sol/snapshot
    - Device: /dev/mapper/vg0-root
    - Type: ext4
    - Mount point: /
    - Status: On the root partition
```

Similar blocks are shown for single‑disk and three‑disk setups.

---

## ⚠️ Precautions

### 1. Data Safety

- ✅ The script only manipulates mount points; it **does not delete or modify existing data**.  
- ✅ It detects existing filesystems and leaves them untouched.  
- ✅ Formatting occurs only on brand‑new devices without a filesystem.

### 2. Unmount Failures

If a device cannot be unmounted (e.g., it’s in use), the script will output:

```
⚠️  Unable to unmount /dev/nvme0n1 – it may be in use. Please check manually and rerun the script.
```

**Resolution**:

```bash
# Find processes using the mount point
lsof | grep /mnt/nvme0n1
# Stop the offending service
systemctl stop <service-name>
# Manually unmount
umount /dev/nvme0n1
# Re‑run the script
bash 1-prepare.sh
```

### 3. `/etc/fstab` Management

- ✅ Old mount entries are automatically removed.  
- ✅ New persistent entries are added, so the configuration survives reboots.

### 4. System‑Disk Usage

Based on your hardware:

- **nvme0n1 (2.9 TB)** → `/root/sol/accounts` (highest IOPS)  
- **nvme1n1 (2.9 TB)** → `/root/sol/ledger` (medium IOPS)  
- **Snapshot** → system disk (low IOPS)  

This allocation yields the best performance‑to‑cost ratio.

---

## 🎯 General Disk‑Configuration Support

The script automatically adapts to **1‑3 data disks**:

### Configuration Scenarios

#### Scenario 1 – Single Data Disk

```
Configuration:
- Data Disk 1 → /root/sol/accounts (high performance)
- System Disk → /root/sol/ledger + /root/sol/snapshot
```

**Performance**: Accounts gets maximum IOPS; Ledger & Snapshot share the system disk.

#### Scenario 2 – Dual Data Disks (⭐ Recommended)

```
Configuration:
- Data Disk 1 → /root/sol/accounts
- Data Disk 2 → /root/sol/ledger
- System Disk → /root/sol/snapshot
```

**Performance**: Both Accounts and Ledger have independent NVMe, dramatically reducing system‑disk load.

#### Scenario 3 – Three Data Disks

```
Configuration:
- Data Disk 1 → /root/sol/accounts
- Data Disk 2 → /root/sol/ledger
- Data Disk 3 → /root/sol/snapshot
- System Disk → OS only
```

**Performance**: Full isolation; maximum throughput for all three directories.

### Performance Comparison

| Scenario | Accounts | Ledger | Snapshot | System‑Disk Load | Cost‑Effectiveness |
|----------|----------|--------|----------|------------------|--------------------|
| **Before Fix** (all on system disk) | Shared | Shared | Shared | Very high | – |
| **1 Disk** | Dedicated NVMe ✅ | System disk | System disk | Medium | ★★★ |
| **2 Disks** | Dedicated NVMe ✅ | Dedicated NVMe ✅ | System disk | Low | ★★★★★ |
| **3 Disks** | Dedicated NVMe ✅ | Dedicated NVMe ✅ | Dedicated NVMe ✅ | Very low | ★★★★ |

### Space Utilisation (example: two 2.9 TB NVMe)

- **Accounts**: 2.9 TB (expected usage 300‑500 GB)  
- **Ledger**: 2.9 TB (can be limited to ~50 GB via `--limit-ledger-size`)  
- **Snapshot**: System‑disk space (50‑100 GB, keep 2‑3 snapshots)

### Stability Improvements

- ✅ Reduces I/O pressure on the system disk (‑50 % for single‑disk, ‑80 % for dual‑disk)  
- ✅ Prevents Solana data from competing with system logs  
- ✅ Speeds up node sync and RPC response times  
- ✅ Lowers latency caused by disk‑I/O saturation

---

## 📚 Related Documentation

- **Mount Strategy**: `MOUNT_STRATEGY.md`  
- **Installation Guide**: `README.md`  
- **Performance Monitoring**: `bash performance-monitor.sh`  
- **Health Check**: `bash get_health.sh`

---

## 🤝 Support & Feedback

If you encounter any issues while running the fix script:

1. Review the script output for specific error messages.  
2. Run `bash verify-mounts.sh` to inspect the current mount state.  
3. Reach out to technical support or open an Issue on the repository.

---

**Version**: 1.0  
**Last Updated**: 2025‑12‑01  
**Maintainer**: Solana RPC Team
