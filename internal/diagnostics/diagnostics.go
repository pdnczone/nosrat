// Package diagnostics implements `nosrat diagnose`: a checklist that
// pinpoints exactly which layer of the stack is broken, with the shell
// command to fix it, instead of a generic "tunnel is down".
package diagnostics

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/pdnczone/nosrat/internal/config"
	"github.com/pdnczone/nosrat/internal/gre"
	"github.com/pdnczone/nosrat/internal/ipsec"
)

type CheckResult struct {
	Name   string
	OK     bool
	Detail string
	Fix    string
}

func run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	return string(out), err
}

func RunAll(c *config.Config) []CheckResult {
	var results []CheckResult

	// 1. Kernel support for GRE
	if out, err := run("sh", "-c", "test -e /proc/sys/net/ipv4/conf/all/forwarding"); err == nil {
		results = append(results, CheckResult{"Kernel support", true, "net.ipv4 sysctls present", ""})
	} else {
		results = append(results, CheckResult{"Kernel support", false, out, "check that you are running a Linux kernel with CONFIG_NET enabled (should be default on Ubuntu 24.04)"})
	}

	// 2. GRE module
	if out, _ := run("sh", "-c", "lsmod | grep -E '^(ip_gre|gre)\\b'"); strings.TrimSpace(out) != "" {
		results = append(results, CheckResult{"GRE module", true, strings.TrimSpace(out), ""})
	} else if _, err := run("modprobe", "-n", "ip_gre"); err == nil {
		results = append(results, CheckResult{"GRE module", true, "ip_gre loadable (built-in or available as module)", ""})
	} else {
		results = append(results, CheckResult{"GRE module", false, "ip_gre not loaded/loadable", "modprobe ip_gre"})
	}

	// 3. XFRM
	if out, err := run("sh", "-c", "ip xfrm state 2>&1"); err == nil {
		results = append(results, CheckResult{"XFRM", true, "ip xfrm accessible", ""})
		_ = out
	} else {
		results = append(results, CheckResult{"XFRM", false, out, "ensure kernel has XFRM support (CONFIG_XFRM); should be default on Ubuntu 24.04 kernels"})
	}

	// 4. strongSwan installed & running (unit is "strongswan" on RHEL/Alpine,
	// "strongswan-starter" on Debian/Ubuntu).
	swActive := false
	for _, unit := range []string{"strongswan", "strongswan-starter"} {
		if out, err := run("systemctl", "is-active", unit); err == nil && strings.TrimSpace(out) == "active" {
			swActive = true
			break
		}
	}
	if swActive {
		results = append(results, CheckResult{"strongSwan", true, "strongSwan active", ""})
	} else {
		results = append(results, CheckResult{"strongSwan", false, "not active", "systemctl start strongswan (or strongswan-starter)"})
	}

	// 5. IKE state
	sa := ipsec.Status(c)
	if sa.IKEState == "ESTABLISHED" {
		results = append(results, CheckResult{"IKE", true, "ESTABLISHED", ""})
	} else {
		results = append(results, CheckResult{"IKE", false, "state=" + sa.IKEState, "swanctl --initiate --child " + c.TunnelName + "-esp ; check swanctl --log for the negotiation failure reason"})
	}

	// 6. ESP state
	if sa.ESPState == "INSTALLED" {
		results = append(results, CheckResult{"ESP", true, "INSTALLED, cipher=" + sa.Encryption + " pfs=" + sa.PFSGroup, ""})
	} else {
		results = append(results, CheckResult{"ESP", false, "state=" + sa.ESPState, "check firewall allows UDP 500/4500 and ESP/GRE between both public IPs"})
	}

	// 7. GRE interface
	link, _ := gre.Status(c.TunnelName)
	if link.Exists && link.OperState == "UP" {
		results = append(results, CheckResult{"GRE interface", true, fmt.Sprintf("%s UP mtu=%d", link.IfName, link.MTU), ""})
	} else {
		results = append(results, CheckResult{"GRE interface", false, fmt.Sprintf("exists=%v state=%s", link.Exists, link.OperState), "nosrat create && nosrat start"})
	}

	// 8. Routing
	if out, err := run("ip", "route", "get", c.Remote.PublicIP); err == nil {
		results = append(results, CheckResult{"Routing", true, strings.TrimSpace(out), ""})
	} else {
		results = append(results, CheckResult{"Routing", false, out, "check default route / peer reachability: ip route get " + c.Remote.PublicIP})
	}

	// 9. Firewall
	if out, err := run("nft", "list", "table", "inet", "nosrat"); err == nil && strings.Contains(out, "nosrat") {
		results = append(results, CheckResult{"Firewall", true, "inet nosrat table loaded", ""})
	} else {
		results = append(results, CheckResult{"Firewall", false, out, "nosrat start   (re-applies the nftables ruleset)"})
	}

	// 10. MTU
	if link.Exists && link.MTU == c.MTU.Value {
		results = append(results, CheckResult{"MTU", true, fmt.Sprintf("%d (matches config)", link.MTU), ""})
	} else if link.Exists {
		results = append(results, CheckResult{"MTU", false, fmt.Sprintf("interface=%d config=%d", link.MTU, c.MTU.Value), fmt.Sprintf("ip link set dev %s mtu %d", c.TunnelName, c.MTU.Value)})
	} else {
		results = append(results, CheckResult{"MTU", false, "interface missing", "nosrat create"})
	}

	// 11. Connectivity (end-to-end ping over GRE)
	if out, err := run("ping", "-c", "3", "-w", "5", c.RemoteGREAddr()); err == nil && strings.Contains(out, " 0% packet loss") {
		results = append(results, CheckResult{"Connectivity", true, "0% packet loss to " + c.RemoteGREAddr(), ""})
	} else {
		results = append(results, CheckResult{"Connectivity", false, strings.TrimSpace(out), "check IKE/ESP/GRE checks above first; if those are OK, check remote-side firewall/routing"})
	}

	return results
}

func Print(results []CheckResult) {
	for _, r := range results {
		mark := "[✓]"
		if !r.OK {
			mark = "[✗]"
		}
		fmt.Printf("%s %-16s %s\n", mark, r.Name, r.Detail)
		if !r.OK && r.Fix != "" {
			fmt.Printf("     -> fix: %s\n", r.Fix)
		}
	}
}
