#!/bin/bash
# ==================================================================
# Solana Pruned RPC Node - Mainnet Follower
# ==================================================================
# Configuration:
# - No Voting (Mainnet Follower)
# - Pruned Ledger (80GB limit)
# - No Accounts Index (Lightweight)
# - No Store Ledger
# - Full RPC API (with limitations due to no index)
# - Dynamic Port Range: 8000-8010
# ==================================================================

export RUST_LOG=warn
export RUST_BACKTRACE=1

# Auto-detect Public IP for gossip
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
if [[ -z "$PUBLIC_IP" ]]; then
    echo "ERROR: Could not detect public IP. Please set it manually."
    exit 1
fi

echo "Starting Solana Pruned RPC Node..."
TOTAL_MEM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

echo "✅ TIER 1: 16GB OPTIMIZED STANDARD CONFIGURATION"
echo "   System RAM: ${TOTAL_MEM_GB}GB | Target Peak: ~105-120GB"
echo "   RPC Threads: 8 | Accounts Cache: 1.5GB | Index Bins: 2048"
echo "   ✅ Transaction History: ENABLED"
echo "   📊 Full RPC features with slightly conservative parameters"
echo "=================================================================="
echo "Ledger Limit: 80,000,000 (~80GB)"

exec /usr/local/solana/bin/solana-validator \
 --geyser-plugin-config /root/sol/bin/yellowstone-config.json \
 --ledger /root/sol/ledger \
 --accounts /root/sol/accounts \
 --identity /root/sol/bin/validator-keypair.json \
 --snapshots /root/sol/snapshot \
 --log /root/solana-rpc.log \
 --entrypoint entrypoint.mainnet-beta.solana.com:8001 \
 --entrypoint entrypoint2.mainnet-beta.solana.com:8001 \
 --entrypoint entrypoint3.mainnet-beta.solana.com:8001 \
 --entrypoint entrypoint4.mainnet-beta.solana.com:8001 \
 --entrypoint entrypoint5.mainnet-beta.solana.com:8001 \
 --known-validator Certusm1sa411sMpV9FPqU5dXAYhmmhygvxJ23S6hJ24 \
 --known-validator 7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2 \
 --known-validator GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ \
 --known-validator CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S \
 --known-validator DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ \
 --expected-genesis-hash 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d \
 --only-known-rpc --no-port-check \
 --dynamic-port-range 8000-8025 --gossip-port 8001 \
 --rpc-bind-address 0.0.0.0 --rpc-port 8899 \
 --full-rpc-api --private-rpc --rpc-threads 4 \
 --rpc-max-multiple-accounts 50 \
 --rpc-max-request-body-size 20971520 \
 --rpc-bigtable-timeout 180 --rpc-send-retry-ms 1000 \
 --health-check-slot-distance 150 \
 --no-voting --allow-private-addr --bind-address 0.0.0.0 \
 --disable-accounts-disk-index \
 --limit-ledger-size 80000000 \
 --no-snapshot-fetch \
 --no-os-network-limits-test \
 --no-accounts-db-index-hashing \
 --wal-recovery-mode skip_any_corrupted_record
