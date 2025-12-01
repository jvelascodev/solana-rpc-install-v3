#!/bin/bash
set -euo pipefail

# ============================================
# Step 3: Download snapshot and start Solana RPC node
# ============================================
# Prerequisite: Must have run 1-prepare.sh and 2-install-solana.sh, then reboot the system
# ============================================

SERVICE_NAME=${SERVICE_NAME:-sol}
LEDGER=${LEDGER:-/root/sol/ledger}
ACCOUNTS=${ACCOUNTS:-/root/sol/accounts}
SNAPSHOT=${SNAPSHOT:-/root/sol/snapshot}
LOGFILE=/root/solana-rpc.log

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run as root: sudo bash $0" >&2
  exit 1
fi

echo "============================================"
echo "Step 3: Download snapshot and start node"
echo "============================================"
echo ""

# Verify system optimizations are applied
echo "==> 1) Verifying system optimizations..."
echo ""

# Verify BBR congestion control
bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
if [[ "$bbr" == "bbr" ]]; then
  echo "  ✅ BBR congestion control: enabled"
else
  echo "  ⚠️  BBR congestion control: not enabled (current: $bbr)"
fi

# Verify TCP buffer size
rmem=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "0")
if [[ "$rmem" == "536870912" ]]; then
  echo "  ✅ TCP buffer: 512MB (max)"
else
  echo "  ⚠️  TCP buffer: not at max (current: $rmem, expected: 536870912)"
fi

# Verify disk read-ahead settings
for dev in /sys/block/nvme* /sys/block/sd*; do
  [[ -e "$dev" ]] || continue
  devname=$(basename "$dev")
  ra=$(cat "$dev/queue/read_ahead_kb" 2>/dev/null || echo "0")
  if [[ "$ra" == "32768" ]]; then
    echo "  ✅ Disk read-ahead: 32MB ($devname)"
  else
    echo "  ⚠️  Disk read-ahead: not at max (current: ${ra}KB, expected: 32768KB)"
  fi
  break
done

echo ""
echo "==> 2) Stopping existing service..."
systemctl stop $SERVICE_NAME 2>/dev/null || true
sleep 2
echo "  ✅ Service stopped"

echo ""
echo "==> 3) Cleaning old data (preserving identity keys)..."
rm -f "$LOGFILE" || true

# Clean directories
dirs=("$LEDGER" "$ACCOUNTS" "$SNAPSHOT")
for dir in "${dirs[@]}"; do
  if [[ -d "$dir" ]]; then
    echo "  - Cleaning directory: $dir"
    rm -rf "$dir"/* "$dir"/.[!.]* "$dir"/..?* || true
  else
    echo "  - Creating directory: $dir"
    mkdir -p "$dir"
  fi
done
echo "  ✅ Old data cleaned"

echo ""
echo "==> 4) Preparing snapshot download tool..."
cd /root

# Install dependencies
echo "  - Installing Python dependencies..."
apt-get update -qq
apt-get install -y python3-venv git >/dev/null 2>&1

# Clone or update solana-snapshot-finder
if [[ ! -d "solana-snapshot-finder" ]]; then
  echo "  - Cloning solana-snapshot-finder repository..."
  git clone https://github.com/0xfnzero/solana-snapshot-finder >/dev/null 2>&1
else
  echo "  - Updating solana-snapshot-finder repository..."
  cd solana-snapshot-finder
  git pull >/dev/null 2>&1
  cd ..
fi

# Create virtual environment
cd solana-snapshot-finder
if [[ ! -d "venv" ]]; then
  echo "  - Creating Python virtual environment..."
  python3 -m venv venv
fi

echo "  - Installing Python packages..."
source ./venv/bin/activate
pip3 install --upgrade pip >/dev/null 2>&1
pip3 install -r requirements.txt >/dev/null 2>&1

echo "  ✅ Tool preparation complete"

echo ""
echo "==> 5) Downloading snapshot (1-3 hours, depending on network speed)..."
echo ""
echo "  🚀 Expected download speed: 500MB - 2GB/s (optimised)"
echo ""

# Run snapshot finder
python3 snapshot-finder.py --snapshot_path "$SNAPSHOT"

echo ""
echo "  ✅ Snapshot download completed"

echo ""
echo "==> 6) Starting Solana RPC node..."
systemctl start $SERVICE_NAME

# Wait for service to start
sleep 3

# Check status
if systemctl is-active --quiet $SERVICE_NAME; then
  echo "  ✅ Node started"
else
  echo "  ❌ Node failed to start"
  echo ""
  echo "Check logs:"
  systemctl status $SERVICE_NAME --no-pager -l
  exit 1
fi

echo ""
echo "============================================"
echo "✅ Step 3 complete: Node successfully started!"
echo "============================================"
echo ""
echo "📊 Node status:"
echo "  - Service: running"
echo "  - Snapshot: downloaded"
echo "  - Estimated sync time: 30-60 minutes"
echo ""
echo "📋 Monitoring commands:"
echo ""
echo "  Real-time logs:"
echo "    journalctl -u $SERVICE_NAME -f"
echo "    or tail -f $LOGFILE"
echo ""
echo "  Performance monitoring:"
echo "    bash /root/performance-monitor.sh snapshot"
echo ""
echo "  Health check:"
echo "    /root/get_health.sh"
echo ""
echo "  Catch-up status:"
echo "    /root/catchup.sh"
echo ""
echo "🎯 Key metrics:"
echo "  - Memory peak should be < 110GB"
echo "  - CPU usage < 70%"
echo "  - Catch-up latency < 100 slots"
echo ""
echo "✅ Done! RPC node is syncing blockchain data..."
echo ""
