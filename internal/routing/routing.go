// Package routing configures IP forwarding, rp_filter, and static routes
// over the GRE interface so traffic between LAN A and LAN B actually flows.
package routing

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/pdnczone/nosrat/internal/config"
)

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// sysctlSet writes a runtime value AND persists it in
// /etc/sysctl.d/99-nosrat.conf so it survives reboot.
func sysctlSet(key, value string) error {
	if _, err := run("sysctl", "-w", key+"="+value); err != nil {
		return err
	}
	return persistSysctl(key, value)
}

func persistSysctl(key, value string) error {
	const path = "/etc/sysctl.d/99-nosrat.conf"
	line := key + " = " + value + "\n"

	existing, _ := os.ReadFile(path)
	lines := strings.Split(string(existing), "\n")
	found := false
	for i, l := range lines {
		if strings.HasPrefix(strings.TrimSpace(l), key+" ") || strings.HasPrefix(strings.TrimSpace(l), key+"=") {
			lines[i] = strings.TrimSuffix(line, "\n")
			found = true
		}
	}
	var out string
	if found {
		out = strings.Join(lines, "\n")
	} else {
		out = strings.Join(lines, "\n") + line
	}
	return os.WriteFile(path, []byte(strings.TrimLeft(out, "\n")), 0644)
}

// Enable turns on the kernel settings a GRE-over-IPsec forwarder needs:
//   - net.ipv4.ip_forward=1
//   - rp_filter=2 ("loose") on the GRE interface
func Enable(c *config.Config) error {
	if err := sysctlSet("net.ipv4.ip_forward", "1"); err != nil {
		return err
	}
	for _, iface := range []string{"all", c.TunnelName} {
		key := fmt.Sprintf("net.ipv4.conf.%s.rp_filter", iface)
		if err := sysctlSet(key, "2"); err != nil {
			return err
		}
	}
	return nil
}

// ApplyStaticRoutes pushes configured static routes with the GRE peer as
// next-hop. Before creating routes, verify that the route to the remote
// PUBLIC IP remains reachable through the physical/WAN interface to prevent
// routing loops.
func ApplyStaticRoutes(c *config.Config) error {
	for _, r := range c.Routing.StaticRoutes {
		nextHop := c.RemoteGREAddr()
		if !r.ViaGRE {
			continue
		}
		// Idempotent: replace rather than add.
		if _, err := run("ip", "route", "replace", r.To, "via", nextHop, "dev", c.TunnelName); err != nil {
			return fmt.Errorf("route %s via %s: %w", r.To, nextHop, err)
		}
	}
	return nil
}

// FlushStaticRoutes removes routes previously installed by ApplyStaticRoutes.
func FlushStaticRoutes(c *config.Config) {
	for _, r := range c.Routing.StaticRoutes {
		_, _ = run("ip", "route", "del", r.To, "dev", c.TunnelName)
	}
}

// List returns `ip route` output relevant to the tunnel.
func List(c *config.Config) (string, error) {
	out, err := run("ip", "route", "show", "dev", c.TunnelName)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out) == "" {
		return "(no routes on " + c.TunnelName + ")", nil
	}
	return out, nil
}

// RemoveSysctlConfig removes the sysctl configuration file.
func RemoveSysctlConfig() error {
	return os.Remove("/etc/sysctl.d/99-nosrat.conf")
}
