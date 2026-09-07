// Package cmd provides centralized command execution with timeouts and error handling.
package cmd

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Runner executes external commands with consistent error handling.
type Runner struct {
	timeout time.Duration
}

// NewRunner creates a new command runner with the specified timeout.
func NewRunner(timeout time.Duration) *Runner {
	return &Runner{timeout: timeout}
}

// Run executes a command and returns output or error.
func (r *Runner) Run(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), r.timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return string(out), fmt.Errorf("%s %s: command timed out after %v", name, strings.Join(args, " "), r.timeout)
		}
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// RunShell executes a shell command with timeout.
func (r *Runner) RunShell(command string) (string, error) {
	return r.Run("sh", "-c", command)
}

// DefaultRunner is the default command runner with 30s timeout.
var DefaultRunner = NewRunner(30 * time.Second)
