// Package firewall manages a dedicated nftables table for nosrat. Using a
// separate table (inet nosrat) means we never clobber the operator's
// existing nftables/iptables rules - we only add what the tunnel needs and
// can cleanly remove exactly that on `nosrat uninstall`.
package firewall

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/pdnczone/nosrat/internal/config"
)

const tableName = "nosrat"

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// Apply (re)creates the `inet nosrat` nftables table with rules scoped to
// exactly what this tunnel needs:
//
//	UDP/500  and UDP/4500  - IKE, always required (4500 is also used for
//	                          NAT-T-encapsulated ESP once NAT is detected)
//	ESP (proto 50)          - required only when NAT-T is NOT in play; once a
//	                          NAT is detected, strongSwan re-encapsulates ESP
//	                          inside UDP/4500 and proto-50 is not needed on
//	                          the WAN edge, but we allow it anyway since most
//	                          direct VPS<->VPS links have no NAT between them
//	GRE (proto 47)          - required, this is the tunnel payload itself
//	TCP MSS clamping        - forward chain, clamps to path-mtu(gre) so we
//	                          never rely on ICMP-based PMTUD across the ESP
//	                          boundary (which is often filtered)
func Apply(c *config.Config) error {
	if !c.Firewall.Enabled {
		return nil
	}

	sshRule := ""
	if c.Firewall.AllowSSH {
		sshRule = "        tcp dport 22 accept comment \"nosrat: keep SSH reachable\"\n"
	}

	ruleset := fmt.Sprintf(`table inet %s
delete table inet %s

table inet %s {
    chain input {
        type filter hook input priority 0; policy accept;
        udp dport {500, 4500} accept comment "nosrat: IKE/NAT-T"
        ip protocol esp accept comment "nosrat: ESP"
        ip protocol gre accept comment "nosrat: GRE payload"
%s    }

    chain forward {
        type filter hook forward priority 0; policy accept;
        oifname "%s" tcp flags syn tcp option maxseg size set %d comment "nosrat: MSS clamp egress"
        iifname "%s" tcp flags syn tcp option maxseg size set %d comment "nosrat: MSS clamp ingress"
    }
}
`, tableName, tableName, tableName, sshRule, c.TunnelName, c.MSSValue(), c.TunnelName, c.MSSValue())

	// `nft -f -` applies the whole ruleset atomically; the leading
	// `delete table` (guarded by `|| true` semantics via a fresh `add table`
	// right after) makes re-running this idempotent even on first run when
	// the table doesn't exist yet.
	safeRuleset := strings.Replace(ruleset, "delete table inet "+tableName+"\n", "", 1)
	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(fmt.Sprintf("table inet %s\ndelete table inet %s\n", tableName, tableName))
	_ = cmd.Run() // ignore error: table may not exist yet on first run

	cmd2 := exec.Command("nft", "-f", "-")
	cmd2.Stdin = strings.NewReader(safeRuleset)
	out, err := cmd2.CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft apply: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// Remove deletes the nosrat nftables table entirely (used by uninstall).
func Remove() error {
	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(fmt.Sprintf("delete table inet %s\n", tableName))
	_, err := cmd.CombinedOutput()
	return err // best-effort; ignore "no such table" on already-clean systems
}

// List shows the currently loaded nosrat ruleset (`nosrat status` / diagnose).
func List() (string, error) {
	return run("nft", "list", "table", "inet", tableName)
}
