#!/usr/bin/env bash
set -euo pipefail

# Run deviceconnectfs kernel-client e2e using the v9fs/test methodology.
# This script is meant to run inside ghcr.io/v9fs/docker:v2.0.0.

VMLINUX_TAG="${V9FS_TEST_KERNEL_TAG:-kernel-main}"
KERNEL_IMAGE="${KERNEL_IMAGE:-/opt/v9fs/Image}"
INITRD="${INITRD:-/opt/v9fs/initrd-deviceconnectfs.cpio}"
QEMULOG="${QEMULOG:-/opt/v9fs/qemu.log}"
PIDFILE="${PIDFILE:-/opt/v9fs/qemu.pid}"

DEVICECONNECTFS_PORT="${DEVICECONNECTFS_PORT:-5642}"

echo "[host] fetching kernel Image (${VMLINUX_TAG})"
curl -fsSL "https://github.com/v9fs/test/releases/download/${VMLINUX_TAG}/Image" -o "${KERNEL_IMAGE}"

echo "[host] building deviceconnectfs + guest binaries"
# Keep build artifacts outside the bind-mounted repo; the workspace is often
# mounted read-only (or non-root-unwritable) inside v9fs/docker.
BIN_DIR="${BIN_DIR:-/opt/v9fs/_bin}"
mkdir -p "${BIN_DIR}"
cd /opt/v9fs/deviceconnectfs
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -buildvcs=false -o "${BIN_DIR}/go9p-deviceconnectfs" ./cmd/go9p-deviceconnectfs
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -buildvcs=false -o "${BIN_DIR}/kernel9p-deviceconnectfs-e2e" ./cmd/kernel9p-deviceconnectfs-e2e

echo "[host] building u-root initrd (uinitcmd: mount hostshare -> chroot -> guest-e2e-deviceconnectfs.sh)"
UROOTVERS="${UROOTVERS:-v0.16.0}"
UROOT_DIR="$(GO111MODULE=on go list -f '{{.Dir}}' -m github.com/u-root/u-root@${UROOTVERS})"
mkdir -p /opt/v9fs/uimage-deviceconnectfs
cd /opt/v9fs/uimage-deviceconnectfs
rm -f go.work go.work.sum "${INITRD}" || true
go work init "${UROOT_DIR}"

UINIT_CMD="/bbin/gosh -c \"mkdir -p /mnt/9; mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 hostshare /mnt/9; KERNEL9P_TCP_ADDR=10.0.2.2 KERNEL9P_TCP_PORT=${DEVICECONNECTFS_PORT} chroot /mnt/9 /bin/bash /opt/v9fs/deviceconnectfs/scripts/v9fs/guest-e2e-deviceconnectfs.sh; shutdown -h now\""
GOWORK=/opt/v9fs/uimage-deviceconnectfs/go.work /opt/v9fs/go/bin/u-root   -o "${INITRD}"   -files /opt/v9fs/deviceconnectfs/scripts/v9fs/guest-e2e-deviceconnectfs.sh:guest-e2e-deviceconnectfs.sh   -initcmd=/bbin/init   -uinitcmd="${UINIT_CMD}"   github.com/u-root/u-root/cmds/core/{init,gosh,mount,chroot,shutdown,poweroff,mkdir}

echo "[host] starting go9p-deviceconnectfs server on :${DEVICECONNECTFS_PORT}"
"${BIN_DIR}/go9p-deviceconnectfs" -addr "0.0.0.0:${DEVICECONNECTFS_PORT}" >/dev/null 2>&1 &
DEVICECONNECTFS_PID=$!
trap 'kill ${DEVICECONNECTFS_PID} >/dev/null 2>&1 || true' EXIT

echo "[host] starting QEMU"
rm -f "${PIDFILE}" || true
ARCH=aarch64 INITRD="${INITRD}" KERNEL="${KERNEL_IMAGE}" QEMULOG="${QEMULOG}" PIDFILE="${PIDFILE}"   bash /opt/v9fs/deviceconnectfs/scripts/v9fs/qemu.bash

QEMUPID="$(cat "${PIDFILE}")"
echo "[host] QEMU pid=${QEMUPID}"

echo "[host] waiting for QEMU exit"
while kill -0 "${QEMUPID}" >/dev/null 2>&1; do
  sleep 2
done

echo "--- QEMU log tail (${QEMULOG}) ---"
tail -250 "${QEMULOG}" || true

grep -q "PASS: kernel9p deviceconnectfs e2e" "${QEMULOG}"
echo "[host] PASS"
