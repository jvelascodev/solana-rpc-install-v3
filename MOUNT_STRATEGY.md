# Solana RPC Node Storage Mount Strategy

## 📊 Current Mount Configuration (Optimal)

### Disk Allocation

```
nvme1n1 (1.7T NVMe)     → /root/sol/accounts
nvme0n1p2 (1.7T NVMe)   → / (system partition)
                           ├─ /root/sol/ledger
                           └─ /root/sol/snapshot
```

### Performance & Space Analysis

| Mount point | Disk | Used | Available | Utilisation | I/O characteristics |
|------------|------|------|-----------|--------------|----------------------|
| `/root/sol/accounts` | nvme1n1 | 424GB | 1.3TB | 26% | 🔴 Extremely high‑frequency random read/write |
| `/root/sol/ledger` | nvme0n1p2 | - | 1.3TB | 23% (total) | 🟡 Continuous sequential writes |
| `/root/sol/snapshot` | nvme0n1p2 | - | 1.3TB | 23% (total) | 🟢 Periodic read/write |

## 🎯 Design Principles

### 1. Accounts directory (most critical)

- **Data type**: account state database (RocksDB)
- **I/O pattern**: extremely high‑frequency random read/write
- **Space requirement**: 300‑500 GB+ (grows over time)
- **Performance impact**: directly affects validator sync speed and RPC response time
- **Mount strategy**: ✅ Dedicated nvme1n1 to guarantee maximum IOPS

### 2. Ledger directory

- **Data type**: blockchain history data
- **I/O pattern**: continuous sequential writes, occasional reads
- **Space requirement**: controllable (use `--limit-ledger-size` to cap at 50 GB)
- **Performance impact**: moderate, mainly write latency
- **Mount strategy**: ✅ System disk is sufficient; no separate disk needed

### 3. Snapshot directory

- **Data type**: snapshot archive files
- **I/O pattern**: periodic large‑file read/write (download / generate snapshots)
- **Space requirement**: 50‑100 GB (2‑3 snapshots)
- **Performance impact**: low, not real‑time data
- **Mount strategy**: ✅ System disk is sufficient; shares with ledger

## 🔧 Automatic Mount Priority

The script `1-prepare.sh` automatically detects available disks and mounts them by priority:

```bash
# Priority order (high to low)
1. First available disk → /root/sol/accounts   (highest performance need)
2. Second available disk → /root/sol/ledger   (medium performance need)
3. Third available disk → /root/sol/snapshot (low performance need)
```

**Current server**:

- ✅ nvme1n1 → accounts (only data disk, assigned to the most demanding accounts)
- ⏺️ ledger → system disk (no second disk, using system disk)
- ⏺️ snapshot → system disk (no third disk, using system disk)

## 📈 Scaling Recommendations

### If you need further performance optimisation

**Option 1: Add a second NVMe (recommended)**

```
nvme1n1   → /root/sol/accounts
New NVMe  → /root/sol/ledger + /root/sol/snapshot
nvme0n1p2 → / (system partition)
```

**Benefit**: ledger writes no longer affect the system disk, resulting in a more stable system.

**Option 2: Add two NVMe drives (high performance)**

```
nvme1n1   → /root/sol/accounts
New NVMe 1 → /root/sol/ledger
New NVMe 2 → /root/sol/snapshot
nvme0n1p2 → / (system partition)
```

**Benefit**: complete isolation, but cost‑effectiveness is lower because snapshots do not need such high performance.

## ✅ Verify Mount Status

### Check current mounts

```bash
# List block devices and mount points
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Show disk usage for each Solana directory
df -h /root/sol/accounts /root/sol/ledger /root/sol/snapshot

# Show actual mount lines for NVMe devices
mount | grep nvme
```

### Expected output

```
nvme1n1                 1.7T  disk  /root/sol/accounts
nvme0n1                 1.7T  disk
├─nvme0n1p1             512M  part  /boot/efi
└─nvme0n1p2             1.7T  part  /
```

## 🔍 Performance Monitoring

### I/O monitoring commands

```bash
# Real‑time I/O monitoring
iostat -xm 2 nvme0n1 nvme1n1

# Disk performance test (random read)
fio --name=randread --ioengine=libaio --iodepth=16 --rw=randread \
    --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=60 \
    --filename=/root/sol/accounts/test

# Clean up test file
rm -f /root/sol/accounts/test
```

### Expected performance metrics

- **accounts (nvme1n1)**: IOPS > 100 k, latency < 1 ms
- **system disk (nvme0n1p2)**: IOPS > 50 k, latency < 2 ms

## 📝 Troubleshooting

### Issue 1: accounts mount disappears

```bash
# Check fstab entry
cat /etc/fstab | grep accounts

# Manually mount
sudo mount /dev/nvme1n1 /root/sol/accounts

# Verify
df -h /root/sol/accounts
```

### Issue 2: Disk space shortage

```bash
# Check ledger size limit
systemctl status sol | grep limit-ledger-size

# Clean old snapshots
cd /root/sol/snapshot
ls -lht *.tar.bz2
rm -f old-snapshot*.tar.bz2
```

### Issue 3: Performance degradation

```bash
# Check disk health
sudo smartctl -a /dev/nvme1n1
sudo smartctl -a /dev/nvme0n1

# Check I/O wait
iostat -x 2
```

## 🎓 Best‑Practice Summary

✅ **DO**:
- Keep `accounts` on its own fastest disk.
- Use `--limit-ledger-size` to control ledger growth.
- Regularly clean old snapshots (keep the latest 2‑3).
- Monitor disk space and I/O performance.

❌ **DON’T**:
- Mix `accounts` with other data on the same disk.
- Wait until the system disk is full before cleaning data.
- Disable snapshot size limits.
- Change mount points arbitrarily in production.

## 📚 Related Files

- **Mount script**: `1-prepare.sh` (auto‑detects and mounts)
- **Validator config**: `validator-*.sh` (storage path settings)
- **Restart script**: `restart_node.sh` (snapshot download path)
- **Monitoring script**: `performance-monitor.sh` (disk performance monitoring)

---

**Document version**: 1.0
**Last updated**: 2025-11-29
**Maintainer**: Solana RPC Team
