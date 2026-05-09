//go:build !linux

package main

import (
	"fmt"
	"runtime"
)

func platformMount9P(_, _, _ string) error {
	return fmt.Errorf("platformMount9P unsupported on GOOS=%s (this binary is meant for linux guests only)", runtime.GOOS)
}

func platformUnmount(_ string) error {
	return fmt.Errorf("platformUnmount unsupported on GOOS=%s (this binary is meant for linux guests only)", runtime.GOOS)
}
