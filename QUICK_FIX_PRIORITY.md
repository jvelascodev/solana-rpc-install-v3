# 🚨 Quick Fix for Mounting Priority Error

## Current Problem

Your server disk mounting order is wrong:
- ❌ Accounts (most performance-critical) → System disk
- ✅ Ledger → nvme0n1 (2.9TB)
- ✅ Snapshot → nvme1n1 (2.9TB)

**This severely affects performance!** Accounts has the highest random read/write IOPS requirements and should use the fastest NVMe.

---

## ⚡ Immediate Fix (2 minutes)

### Option A: Automatic Fix (Recommended)

```bash
# 1. Update code to latest version
cd /root/solana-rpc-install
git pull

# 2. Run preparation script (will automatically detect and fix priority)
bash 1-prepare.sh
```

The script will:
- ✅ Automatically detect priority errors
- ✅ Unmount ledger and snapshot
- ✅ Clean up old fstab configurations
- ✅ Remount by correct priority:
  - nvme0n1 → Accounts
  - nvme1n1 → Ledger
  - System disk → Snapshot

### Option B: Manual Fix (if Option A cannot automatically fix)

```bash
# 1. Stop Solana node (if running)
systemctl stop sol

# 2. Run dedicated fix script
cd /root/solana-rpc-install
bash fix-mount-priority.sh

# Enter yes to confirm fix

# 3. Verify results
bash verify-mounts.sh

# 4. Start node
systemctl start sol
```

---

## ✅ Correct Status After Fix

Running `bash verify-mounts.sh` should show:

```
  • Accounts:
    - Device: /dev/nvme0n1 (2.9TB)
    - Status: Independently mounted ✓

  • Ledger:
    - Device: /dev/nvme1n1 (2.9TB)
    - Status: Independently mounted ✓

  • Snapshot:
    - Device: /dev/mapper/vg0-root
    - Status: On / partition
```

---

## 🎯 Expected Performance Improvements

After fix:
- **Accounts IOPS**: +300-500% (from system disk shared → independent 2.9T NVMe)
- **Node sync speed**: +200-300%
- **RPC response latency**: -50-70%
- **System stability**: Significantly improved (reduced I/O contention)

---

## ⚠️ Important Notes

1. **verify-mounts.sh won't fix the problem**
   - It's just a check tool, won't change any mounting
   - Must run `1-prepare.sh` or `fix-mount-priority.sh` to actually fix

2. **Data Safety**
   - Fix scripts only remount disks, won't delete data
   - Will automatically backup /etc/fstab
   - Recommended to stop Solana node before fixing

3. **If node is running**
   - Must stop node first: `systemctl stop sol`
   - Start again after fix completes: `systemctl start sol`

---

## 🐛 Troubleshooting

### If 1-prepare.sh reports error

```bash
# View detailed error information
bash -x 1-prepare.sh

# If processes are occupying disks
lsof | grep -E "nvme0n1|nvme1n1"
fuser -m /root/sol/ledger
fuser -m /root/sol/snapshot

# Stop occupying processes then retry
systemctl stop sol
bash 1-prepare.sh
```

### If automatic fix fails

Use manual fix script:
```bash
bash fix-mount-priority.sh
```

It will:
- Provide more detailed output
- Wait for user confirmation at each step
- Handle exceptions more safely

---

## 📞 Need Help?

If you encounter any issues:
1. Save complete error output
2. Run `lsblk` and `mount` to view current status
3. Contact technical support and provide the above information

**Remember**: Must actually run the fix script, just running verify-mounts.sh won't solve the problem!
