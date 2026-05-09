# deviceconnectfs

A 9P synthetic filesystem that projects a Device Connect-style device/function
model into a navigable namespace, served with
[go9p](https://github.com/lionkov/go9p).

This was originally an example under `p/srv/examples/deviceconnect/` in
`go9p` and is now maintained as a standalone project so it can grow
independently of the core 9P library.

See `[DESIGN.md](./DESIGN.md)` for the full design notes (filesystem shape,
semantics, clone/ctl call pattern, events, and future session ideas).

## Filesystem shape (current)

```text
/
  devices/
    discover
    by-id/
      <device-id>/
        meta
        status
        events/{replay,stream}
        values/<value-name>/value
        values/<value-name>/events/{replay,stream}
        functions/<function-name>/
          about
          schema
          clone
          <call-id>/
            ctl
            data
            error
            stream
```

Function invocation uses the Plan 9 clone pattern: read `clone` to allocate a
per-call directory, write request bytes to `data`, write `call` to `ctl`, then
read the response from `data`. Closing the last open `ctl` reference garbage
collects the call directory.

## Run

```bash
go run ./cmd/go9p-deviceconnectfs -addr 127.0.0.1:5642
```

Flags:

- `-addr <host:port>`: listen address (default `:5642`)
- `-d`: print 9P debug messages

From another terminal you can drive it with any `go9p` client, for example the
session helper from your `go9p` checkout:

```bash
go run /Users/erivan01/src/v9fs/go9p/cmd/go9p-session -net tcp -addr 127.0.0.1:5642
```

Example session commands:

```text
cat /devices/discover
cat /devices/by-id/robot-001/meta
cat /devices/by-id/robot-001/status
read /devices/by-id/robot-001/functions/echo/clone
write /devices/by-id/robot-001/functions/echo/<id>/data hello
write /devices/by-id/robot-001/functions/echo/<id>/ctl call
cat /devices/by-id/robot-001/functions/echo/<id>/data
```

## Mount with the Linux kernel 9p client

```bash
sudo mount -t 9p -o trans=tcp,port=5642,version=9p2000.u,uname=$USER,access=any 127.0.0.1 /mnt/deviceconnectfs
ls /mnt/deviceconnectfs/devices
```

`access=any` keeps kernel-client smoke tests focused on filesystem semantics
rather than synthetic Unix ownership details.

## Tests

```bash
go test ./...
```

The userspace tests exercise discovery, values, events, function invocation,
stream behavior, error files, and ctl-close garbage collection through an
in-process `go9p` client.

## Kernel 9p e2e

The repository includes a QEMU-based smoke path matching the v9fs/test style
used by `go9p-netfs`:

```bash
docker run --rm --privileged --platform linux/arm64   -v "$PWD:/opt/v9fs/deviceconnectfs"   -w /opt/v9fs/deviceconnectfs   -e V9FS_TEST_KERNEL_TAG=kernel-main   ghcr.io/v9fs/docker:v2.0.0   bash /opt/v9fs/deviceconnectfs/scripts/v9fs/ci-e2e-deviceconnectfs.sh
```

## Status

This module currently builds against the `rework` branch of
`github.com/ericvh/go9p` (pinned via a `replace` directive in `go.mod`) until
the changes there are merged upstream into `github.com/lionkov/go9p`.