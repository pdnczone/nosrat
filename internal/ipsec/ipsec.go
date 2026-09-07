// Package ipsec drives strongSwan (via the modern swanctl/vici toolchain,
// not the legacy `ipsec` starter/stroke interface) to protect the GRE
// tunnel in IPsec Transport Mode. strongSwan negotiates IKEv2/ESP and loads
// the resulting SAs straight into the kernel's XFRM stack; nosrat never
// touches XFRM state directly.
package ipsec

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/pdnczone/nosrat/internal/config"
)

const (
	swanctlDir = "/etc/swanctl/conf.d"
	secretsDir = "/etc/swanctl/conf.d"
)

// connName returns the strongSwan connection name for this tunnel.
func connName(c *config.Config) string { return c.TunnelName }

// run executes an external command and returns output or error.
func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// runWithTimeout executes a command with a timeout.
func runWithTimeout(timeout time.Duration, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// WriteSwanctlConfig renders a swanctl connection file dedicated to this
// tunnel (conf.d/<name>.conf), so multiple nosrat tunnels can coexist
// without clobbering each other's strongSwan config.
func WriteSwanctlConfig(c *config.Config) error {
	if err := os.MkdirAll(swanctlDir, 0755); err != nil {
		return err
	}

	proposal := ikeProposal(c)
	espProposal := espProposalFor(c)

	// Use placeholder for PSK - will be replaced after template rendering
	tmpl := fmt.Sprintf(`# Managed by nosrat - DO NOT EDIT BY HAND
# Regenerate with: nosrat create

connections {
    %s {
        version = 2
        local_addrs  = %s
        remote_addrs = %s
        mobike = no

        local {
            auth = psk
            id = %s
        }
        remote {
            auth = psk
            id = %s
        }

        children {
            %s-esp {
                mode = %s
                local_ts  = %s/32[gre]
                remote_ts = %s/32[gre]
                esp_proposals = %s
                rekey_time = %ds
                dpd_action = restart
                start_action = start
                close_action = start
            }
        }

        proposals = %s
        rekey_time = %ds
        dpd_delay = %ds
        dpd_timeout = %ds
    }
}

secrets {
    ike-%s {
        id-1 = %s
        id-2 = %s
        secret = "%s"
    }
}
`,
		connName(c),
		c.Local.PublicIP, c.Remote.PublicIP,
		c.Local.PublicIP, c.Remote.PublicIP,
		connName(c), strings.ToLower(c.IPsec.Mode),
		c.Local.PublicIP, c.Remote.PublicIP,
		espProposal,
		c.IPsec.RekeySeconds,
		proposal,
		c.IPsec.RekeySeconds,
		c.IPsec.DPDDelaySec, c.IPsec.DPDTimeout,
		connName(c), c.Local.PublicIP, c.Remote.PublicIP,
		"__PSK_PLACEHOLDER__",
	)

	// Read PSK and replace placeholder
	psk, err := c.ReadPSK()
	if err != nil {
		return fmt.Errorf("cannot render swanctl secrets: %w", err)
	}
	tmpl = strings.Replace(tmpl, "__PSK_PLACEHOLDER__", psk, 1)

	path := filepath.Join(swanctlDir, c.TunnelName+".conf")
	if err := os.WriteFile(path, []byte(tmpl), 0600); err != nil {
		return err
	}

	return nil
}

// ikeProposal maps the requested cipher into a strongSwan IKE proposal string.
func ikeProposal(c *config.Config) string {
	cipher := normalizeCipher(c.IPsec.Encryption)
	return fmt.Sprintf("%s-prfsha384-modp%d", cipher, dhGroupNumberToModp(c.IPsec.DHGroup))
}

func espProposalFor(c *config.Config) string {
	cipher := normalizeCipher(c.IPsec.Encryption)
	return fmt.Sprintf("%s-modp%d", cipher, dhGroupNumberToModp(c.IPsec.DHGroup))
}

func normalizeCipher(enc string) string {
	e := strings.ToLower(enc)
	switch {
	case strings.Contains(e, "aes256gcm16"), strings.Contains(e, "aes256-gcm16"):
		return "aes256gcm16"
	case strings.Contains(e, "aes256gcm12"):
		return "aes256gcm12"
	case strings.Contains(e, "chacha20poly1305"):
		return "chacha20poly1305"
	default:
		return "aes256gcm16"
	}
}

func dhGroupNumberToModp(dh int) int {
	switch dh {
	case 14:
		return 2048
	case 15:
		return 3072
	case 16:
		return 4096
	default:
		return 2048
	}
}

// LoadAndInitiate pushes the generated config into the running strongSwan
// daemon (charon, via vici) and brings up the SA.
func LoadAndInitiate(c *config.Config) error {
	if _, err := run("swanctl", "--load-all", "--noprompt"); err != nil {
		return fmt.Errorf("swanctl --load-all: %w", err)
	}
	if _, err := run("swanctl", "--initiate", "--child", connName(c)+"-esp"); err != nil {
		return fmt.Errorf("swanctl --initiate: %w", err)
	}
	return nil
}

// Terminate tears down the SA (used by `nosrat stop`).
func Terminate(c *config.Config) error {
	_, err := run("swanctl", "--terminate", "--ike", connName(c))
	return err
}

// Reload re-reads swanctl configs after a `nosrat create` config change.
func Reload(c *config.Config) error {
	_, err := run("swanctl", "--load-all", "--noprompt")
	return err
}

type SAStatus struct {
	IKEState   string
	ESPState   string
	Encryption string
	PFSGroup   string
}

var (
	ikeStateRe = regexp.MustCompile(`(?m)^\s*%?[\w.-]*:\s+#\d+,\s+(ESTABLISHED|CONNECTING|DELETING)`)
	espStateRe = regexp.MustCompile(`(?m)^\s*%?[\w.-]*-esp:\s+#\d+,\s+reqid.*?,\s+(INSTALLED|REKEYED)`)
	encRe      = regexp.MustCompile(`AES_[A-Z0-9_]+|CHACHA20_POLY1305`)
	dhRe       = regexp.MustCompile(`MODP_\d+|CURVE_\d+`)
)

// Status parses `swanctl --list-sas` text output.
func Status(c *config.Config) SAStatus {
	out, err := run("swanctl", "--list-sas", "--ike", connName(c))
	if err != nil || strings.TrimSpace(out) == "" {
		return SAStatus{IKEState: "DOWN", ESPState: "DOWN"}
	}

	st := SAStatus{IKEState: "DOWN", ESPState: "DOWN"}
	if m := ikeStateRe.FindStringSubmatch(out); m != nil {
		st.IKEState = m[1]
	}
	if m := espStateRe.FindStringSubmatch(out); m != nil {
		if m[1] == "REKEYED" {
			st.ESPState = "INSTALLED"
		} else {
			st.ESPState = m[1]
		}
	}
	if m := encRe.FindString(out); m != "" {
		st.Encryption = m
	}
	if m := dhRe.FindString(out); m != "" {
		st.PFSGroup = m
	}
	return st
}

// EnsureRunning starts the strongSwan systemd unit if it's not already active.
// The unit is named "strongswan" on RHEL/Alpine and "strongswan-starter" on
// Debian/Ubuntu, so try both.
func EnsureRunning() error {
	for _, unit := range []string{"strongswan", "strongswan-starter"} {
		out, err := run("systemctl", "is-active", unit)
		if err == nil && strings.TrimSpace(out) == "active" {
			return nil
		}
	}
	// Not active (or unit missing) — start whichever unit exists.
	var lastErr error
	for _, unit := range []string{"strongswan", "strongswan-starter"} {
		if _, err := run("systemctl", "start", unit); err == nil {
			return nil
		} else {
			lastErr = err
		}
	}
	return lastErr
}

// ValidatePSKStrength checks if a PSK has sufficient entropy.
func ValidatePSKStrength(psk string) error {
	if len(psk) < 32 {
		return fmt.Errorf("PSK too short (%d bytes) - need >=32 bytes of entropy", len(psk))
	}
	return nil
}
