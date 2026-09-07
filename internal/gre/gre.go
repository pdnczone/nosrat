// Package gre manages the Linux kernel GRE tunnel interface. It shells out to
// the `ip` binary (iproute2) rather than talking to netlink directly: this
// keeps nosrat dependency-free (no netlink library, no network access needed
// to build it) while still using real kernel networking, not a userspace
// tunnel.
package gre

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	"github.com/pdnc/grectl/internal/config"
)

type LinkStatus struct {
	IfName    string `json:"ifname"`
	OperState string `json:"operstate"`
	MTU       int    `json:"mtu"`
	Exists    bool
}

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// Exists reports whether the GRE interface is already present.
func Exists(name string) bool {
	_, err := run("ip", "link", "show", name)
	return err == nil
}

// Create builds the GRE interface (idempotent: deletes a stale one with a
// mismatched config first, leaves a matching one untouched).
func Create(c *config.Config) error {
	if Exists(c.TunnelName) {
		// Idempotent re-create: tear down and rebuild so config changes apply.
		_ = Delete(c.TunnelName)
	}

	if _, err := run("ip", "tunnel", "add", c.TunnelName,
		"mode", "gre",
		"local", c.Local.PublicIP,
		"remote", c.Remote.PublicIP,
		"ttl", "255",
	); err != nil {
		return fmt.Errorf("creating GRE interface: %w", err)
	}

	if _, err := run("ip", "addr", "add", c.Local.GREIP, "dev", c.TunnelName); err != nil {
		return fmt.Errorf("assigning GRE address: %w", err)
	}

	if _, err := run("ip", "link", "set", "dev", c.TunnelName, "mtu", fmt.Sprint(c.MTU.Value)); err != nil {
		return fmt.Errorf("setting GRE MTU: %w", err)
	}

	return nil
}

// Up brings the interface up.
func Up(name string) error {
	_, err := run("ip", "link", "set", "dev", name, "up")
	return err
}

// Down brings the interface administratively down (keeps it configured).
func Down(name string) error {
	_, err := run("ip", "link", "set", "dev", name, "down")
	return err
}

// Delete removes the GRE interface entirely.
func Delete(name string) error {
	if !Exists(name) {
		return nil
	}
	_, err := run("ip", "tunnel", "del", name)
	return err
}

// Status queries kernel state via `ip -j link show` (JSON output supported
// by modern iproute2 on Ubuntu 24.04).
func Status(name string) (LinkStatus, error) {
	out, err := run("ip", "-j", "link", "show", name)
	if err != nil {
		return LinkStatus{IfName: name, Exists: false}, nil
	}
	var links []struct {
		IfName    string `json:"ifname"`
		OperState string `json:"operstate"`
		MTU       int    `json:"mtu"`
	}
	if jerr := json.Unmarshal([]byte(out), &links); jerr != nil || len(links) == 0 {
		return LinkStatus{IfName: name, Exists: true}, nil
	}
	return LinkStatus{
		IfName:    links[0].IfName,
		OperState: links[0].OperState,
		MTU:       links[0].MTU,
		Exists:    true,
	}, nil
}
