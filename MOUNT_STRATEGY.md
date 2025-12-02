# Solana RPC Node Storage Mounting Strategy

## 📊 Current Mounting Configuration (Optimal Solution)

### Disk Allocation
```
nvme1n1 (1.7T NVMe)     → /root/sol/accounts
nvme0n1p2 (1.7T NVMe)   → / (System Partition)
                          ├─ /root/sol/ledger
                          └─ /root/sol/snapshot
```

### Performance and Space Analysis
| Mount Point | Disk | Used | Available | Usage | I/O Characteristics |
|-------------|------|------|-----------|-------|---------------------|
| `/root/sol/accounts` | nvme1n1 | 424GB | 1.3TB | 26% | 🔴 Extremely high-frequency random read/write |
| `/root/sol/ledger` | nvme0n1p2 | - | 1.3TB | 23% (total) | 🟡 Continuous sequential write |
| `/root/sol/snapshot` | nvme0n1p2 | - | 1.3TB | 23% (total) | 🟢 Periodic read/write |

## 🎯 Design Principles

### 1. Accounts Directory (Most Critical)
- **Data Type**: Account state database (RocksDB)
- **I/O Mode**: Extremely high-frequency random read/write
- **Space Requirements**: 300-500GB+ (continuous growth)
- **Performance Impact**: Directly affects validator sync speed and RPC response time
- **Mounting Strategy**: ✅ Exclusive nvme1n1, ensure highest IOPS

### 2. Ledger Directory
- **Data Type**: Blockchain historical data
- **I/O Mode**: Continuous sequential write, occasional read
- **Space Requirements**: Controllable (limited to 50GB via --limit-ledger-size)
- **Performance Impact**: Medium, mainly write latency
- **Mounting Strategy**: ✅ System disk sufficient, no need for independent disk

### 3. Snapshot Directory
- **Data Type**: Snapshot archive files
- **I/O Mode**: Periodic large file read/write (download/generate snapshots)
- **Space Requirements**: 50-100GB (2-3 snapshots)
- **Performance Impact**: Low, not real-time data
- **Mounting Strategy**: ✅ System disk sufficient, share with ledger

## 🔧 Automatic Mounting Priority

Script `1-prepare.sh` automatically detects available disks and mounts by priority:

```bash
# Priority order (high to low)
1. First available disk → /root/sol/accounts  (highest performance requirement)
2. Second available disk → /root/sol/ledger    (medium performance requirement)
3. Third available disk → /root/sol/snapshot  (low performance requirement)
```

**Current Server**:
- ✅ nvme1n1 → accounts (only data disk, allocated to most needed accounts)
- ⏺️ ledger → system disk (no second disk, use system disk)
- ⏺️ snapshot → system disk (no third disk, use system disk)

## 📈 Expansion Recommendations

### If further performance optimization is needed

**Option 1: Add second NVMe (recommended)**
```
nvme1n1   → /root/sol/accounts
New NVMe  → /root/sol/ledger + /root/sol/snapshot
nvme0n1p2 → / (System Partition)
```
**Benefits**: ledger writes do not affect system disk, system more stable

**Option 2: Add two NVMe (high performance)**
```
nvme1n1   → /root/sol/accounts
New NVMe 1 → /root/sol/ledger
New NVMe 2 → /root/sol/snapshot
nvme0n1p2 → / (System Partition)
```
**Benefits**: Complete isolation, but low cost-effectiveness (snapshot doesn't need such high performance)

## ✅ Verify Mounting Status

### Check Current Mounting
```bash
# View mount points
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# View disk usage
df -h /root/sol/accounts /root/sol/ledger /root/sol/snapshot

# View actual mounting
mount | grep nvme
```

### Expected Output
```
nvme1n1                 1.7T  disk  /root/sol/accounts
nvme0n1                 1.7T  disk
├─nvme0n1p1             512M  part  /boot/efi
└─nvme0n1p2             1.7T  part  /
```

## 🔍 Performance Monitoring

### I/O Monitoring Commands
```bash
# Real-time I/O monitoring
iostat -xm 2 nvme0n1 nvme1n1

# Disk performance test
fio --name=randread --ioengine=libaio --iodepth=16 --rw=randread \
    --bs=4k --direct=1 --size=1G --numjobs=1 --runtime=60 \
    --filename=/root/sol/accounts/test

# Clean up test file
rm -f /root/sol/accounts/test
```

### Expected Performance Metrics
- **accounts (nvme1n1)**: IOPS > 100K, latency < 1ms
- **system disk (nvme0n1p2)**: IOPS > 50K, latency < 2ms

## 📝 Troubleshooting

### Issue 1: accounts mount lost
```bash
# Check fstab
cat /etc/fstab | grep accounts

# Manual mount
sudo mount /dev/nvme1n1 /root/sol/accounts

# Verify
df -h /root/sol/accounts
```

### Issue 2: Insufficient disk space
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

## 🎓 Best Practices Summary

✅ **DO**:
- Keep accounts mounted independently on the fastest disk
- Use `--limit-ledger-size` to control ledger growth
- Regularly clean old snapshots (keep 2-3 latest)
- Monitor disk space and I/O performance

❌ **DON'T**:
- Don't mix accounts with other data on the same mount
- Don't wait until system disk is exhausted to clean data
- Don't disable snapshot limit parameters
- Don't arbitrarily change mount points in production

## 📚 Related Configuration Files

- **Mounting Script**: `1-prepare.sh` (automatic detection and mounting)
- **Validator Configuration**: `validator-*.sh` (storage path configuration)
- **Restart Script**: `restart_node.sh` (snapshot download path)
- **Monitoring Script**: `performance-monitor.sh` (disk performance monitoring)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-29
**Maintainer**: Solana RPC Team
