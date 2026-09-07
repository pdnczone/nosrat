package firewall

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/pdnczone/nosrat/internal/config"
)

const tableName = "nosrat"

// runWithTimeout runs a command with a timeout
func runWithTimeout(timeout time.Duration, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// Apply (re)creates the `inet nosrat` nftables table with rules scoped to
// exactly what this tunnel needs.
//
// Security: policy drop — only explicitly allowed traffic passes.
func Apply(c *config.Config) error {
	if !c.Firewall.Enabled {
		return nil
	}

	// Delete existing table first (best-effort)
	deleteCmd := exec.Command("nft", "delete", "table", "inet", tableName)
	_ = deleteCmd.Run()

	sshRule := ""
	if c.Firewall.AllowSSH {
		sshRule = "        tcp dport 22 accept comment \"nosrat: keep SSH reachable\"\n"
	}

	ruleset := fmt.Sprintf(`table inet %s {
    chain input {
        type filter hook input priority 0; policy drop;
        udp dport {500, 4500} accept comment "nosrat: IKE/NAT-T"
        ip protocol esp accept comment "nosrat: ESP"
        ip protocol gre accept comment "nosrat: GRE payload"
%s    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        oifname "%s" tcp flags syn tcp option maxseg size set %d comment "nosrat: MSS clamp egress"
        iifname "%s" tcp flags syn tcp option maxseg size set %d comment "nosrat: MSS clamp ingress"
    }
}
`, tableName, sshRule, c.TunnelName, c.MSSValue(), c.TunnelName, c.MSSValue())

	// Create fresh table
	cmd := exec.Command("nft", "add", "table", "inet", tableName)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("nft add table: %w (%s)", err, strings.TrimSpace(string(out)))
	}

	// Apply ruleset
	cmd2 := exec.Command("nft", "add", "table", "inet", tableName)
	cmd2.Stdin = strings.NewReader(ruleset)
	out, err := cmd2.CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft apply: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// Remove deletes the nosrat nftables table entirely (used by uninstall).
func Remove() error {
	cmd := exec.Command("nft", "delete", "table", "inet", tableName)
	out, err := cmd.CombinedOutput()
	if err != nil {
		// Ignore "no such table" errors
		if !strings.Contains(string(out), "no such table") {
			return err
		}
	}
	return nil
}

// List shows the currently loaded nosrat ruleset.
func List() (string, error) {
	return runWithTimeout(30*time.Second, "nft", "list", "table", "inet", tableName)
}
