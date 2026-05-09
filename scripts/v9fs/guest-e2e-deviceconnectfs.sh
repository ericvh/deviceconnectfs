#!/usr/bin/env bash
set -euo pipefail

echo "[guest] running inside chroot: $(uname -rm)"

# We are inside the hostshare chroot (container root). Mount the deviceconnectfs
# 9p export over TCP and run the guest test binary. Use /tmp because /mnt may be
# root-owned and non-writable in ghcr.io/v9fs/docker.
MOUNT_PT="${KERNEL9P_MOUNT:-/tmp/deviceconnectfs-kernel-e2e}"

KERNEL9P_TCP_ADDR="${KERNEL9P_TCP_ADDR:-10.0.2.2}"
KERNEL9P_TCP_PORT="${KERNEL9P_TCP_PORT:-5642}"

KERNEL9P_MOUNT="${MOUNT_PT}" KERNEL9P_TCP_ADDR="${KERNEL9P_TCP_ADDR}" KERNEL9P_TCP_PORT="${KERNEL9P_TCP_PORT}"   /opt/v9fs/_bin/kernel9p-deviceconnectfs-e2e   || (echo "[guest] FAIL" && exit 1)

echo "[guest] PASS"
