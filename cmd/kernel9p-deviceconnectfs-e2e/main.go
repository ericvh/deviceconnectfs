package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func must(err error, msg string) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %s: %v\n", msg, err)
		os.Exit(1)
	}
}

func mustIs(err error, target error, msg string) {
	if !errors.Is(err, target) {
		fmt.Fprintf(os.Stderr, "FAIL: %s: got=%v want=%v\n", msg, err, target)
		os.Exit(1)
	}
}

func mustContains(got, want, msg string) {
	if !strings.Contains(got, want) {
		fmt.Fprintf(os.Stderr, "FAIL: %s: %q does not contain %q\n", msg, got, want)
		os.Exit(1)
	}
}

func readTrim(path string) string {
	b, err := os.ReadFile(path)
	must(err, "read "+path)
	return strings.TrimSpace(string(b))
}

func writeAll(path string, data string) {
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	must(err, "open write "+path)
	_, err = io.WriteString(f, data)
	cerr := f.Close()
	must(err, "write "+path)
	must(cerr, "close "+path)
}

func mustExistDir(path string, msg string) {
	st, err := os.Stat(path)
	must(err, msg+" (stat)")
	if !st.IsDir() {
		must(fmt.Errorf("not a directory"), msg)
	}
}

func openCtl(path string) *os.File {
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err == nil {
		fmt.Printf("INFO: opened ctl %s mode=RDWR\n", path)
		return f
	}
	f, err = os.OpenFile(path, os.O_WRONLY, 0)
	if err == nil {
		fmt.Printf("INFO: opened ctl %s mode=WRONLY\n", path)
		return f
	}
	f, err = os.OpenFile(path, os.O_RDONLY, 0)
	must(err, "open ctl "+path)
	fmt.Printf("INFO: opened ctl %s mode=RDONLY\n", path)
	return f
}

func main() {
	mount := os.Getenv("KERNEL9P_MOUNT")
	if mount == "" {
		mount = "/tmp/deviceconnectfs-kernel-e2e"
	}
	tcpAddr := os.Getenv("KERNEL9P_TCP_ADDR")
	if tcpAddr == "" {
		tcpAddr = "10.0.2.2"
	}
	tcpPort := os.Getenv("KERNEL9P_TCP_PORT")
	if tcpPort == "" {
		tcpPort = "5642"
	}

	fmt.Printf("INFO: kernel9p-deviceconnectfs-e2e mount=%s tcp=%s:%s\n", mount, tcpAddr, tcpPort)

	must(os.MkdirAll(mount, 0o777), "mkdir mountpoint")
	mustExistDir(mount, "mountpoint is dir")
	must(platformMount9P(tcpAddr, tcpPort, mount), "mount deviceconnectfs via tcp")
	defer func() { _ = platformUnmount(mount) }()

	devices := filepath.Join(mount, "devices")
	mustExistDir(devices, "root has /devices")

	discover := readTrim(filepath.Join(devices, "discover"))
	mustContains(discover, "sensor-001", "discover lists sensor")
	mustContains(discover, "robot-001", "discover lists robot")

	robot := filepath.Join(devices, "by-id", "robot-001")
	mustExistDir(robot, "robot directory exists")
	mustContains(readTrim(filepath.Join(robot, "meta")), "robot-001", "robot meta")
	mustContains(readTrim(filepath.Join(robot, "status")), "ok", "robot status")

	battery := readTrim(filepath.Join(robot, "values", "battery", "value"))
	if battery == "" {
		must(fmt.Errorf("empty battery value"), "battery value non-empty")
	}

	echoFn := filepath.Join(robot, "functions", "echo")
	mustExistDir(echoFn, "echo function directory exists")
	callID := readTrim(filepath.Join(echoFn, "clone"))
	if callID == "" {
		must(fmt.Errorf("empty call id"), "clone returns call id")
	}
	callDir := filepath.Join(echoFn, callID)
	mustExistDir(callDir, "clone creates call directory")

	dataPath := filepath.Join(callDir, "data")
	ctlPath := filepath.Join(callDir, "ctl")
	writeAll(dataPath, "hello-deviceconnectfs\n")
	writeAll(ctlPath, "call\n")
	mustContains(readTrim(dataPath), "hello-deviceconnectfs", "echo call response")

	// Allocate a second call and verify that closing the last ctl reference removes it.
	gcID := readTrim(filepath.Join(echoFn, "clone"))
	if gcID == "" {
		must(fmt.Errorf("empty gc call id"), "clone returns gc call id")
	}
	gcDir := filepath.Join(echoFn, gcID)
	gcCtl := filepath.Join(gcDir, "ctl")
	f := openCtl(gcCtl)
	must(f.Close(), "close gc ctl")

	var statErr error
	for i := 0; i < 20; i++ {
		_, statErr = os.Stat(gcDir)
		if errors.Is(statErr, os.ErrNotExist) {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	mustIs(statErr, os.ErrNotExist, "call dir removed after last ctl close")

	fmt.Println("PASS: kernel9p deviceconnectfs e2e")
}
