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
	"strconv"
	"strings"

	"github.com/pdnczone/nosrat/internal/config"
)

const (
	swanctlDir = "/etc/swanctl/conf.d"
	secretsDir = "/etc/swanctl/conf.d"
)

// connName returns the strongSwan connection name for this tunnel. It is
// intentionally just the tunnel name itself (e.g. "nosrat") - no extra
// prefix - since that's already how the operator refers to it everywhere
// else (interface name, swanctl file name, CLI messages).
func connName(c *config.Config) string { return c.TunnelName }

// WriteSwanctlConfig renders a swanctl connection file dedicated to this
// tunnel (conf.d/<name>.conf), so multiple nosrat tunnels can coexist
// without clobbering each other's strongSwan config.
func WriteSwanctlConfig(c *config.Config) error {
	if err := os.MkdirAll(swanctlDir, 0755); err != nil {
		return err
	}

	proposal := ikeProposal(c)
	espProposal := espProposalFor(c)

	// esp_proposals in transport mode still uses the same cipher suite; PFS
	// is expressed by re-using a DH group in the ESP proposal too.
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

	psk, err := c.ReadPSK()
	if err != nil {
		return fmt.Errorf("cannot render swanctl secrets: %w", err)
	}
	tmpl = strings.Replace(tmpl, "__PSK_PLACEHOLDER__", psk, 1)

	path := filepath.Join(swanctlDir, c.TunnelName+".conf")
	if err := os.WriteFile(path, []byte(tmpl), 0600); err != nil {
		return err
	}
	// secrets are embedded above with 0600 perms on the whole file, which is
	// the strongSwan-recommended approach for swanctl.conf.d snippets.
	return nil
}

// ikeProposal maps the requested cipher into a strongSwan IKE proposal
// string. Only modern AEAD ciphers + DH>=14 are ever produced (config.go
// already rejects anything weaker at load time; this is defense in depth).
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
	// strongSwan names MODP groups by their bit size, not the raw IKE
	// transform number; group 14 == modp2048, 15 == modp3072, 16 == modp4096.
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

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
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

// Reload re-reads swanctl configs after a `nosrat create` config change,
// without dropping unrelated tunnels managed by the same strongSwan daemon.
func Reload(c *config.Config) error {
	_, err := run("swanctl", "--load-all", "--noprompt")
	return err
}

type SAStatus struct {
	IKEState   string // ESTABLISHED, CONNECTING, DOWN
	ESPState   string // INSTALLED, DOWN
	Encryption string
	PFSGroup   string
}

var (
	ikeStateRe = regexp.MustCompile(`(?m)^\s*%?[\w.-]*:\s+#\d+,\s+(ESTABLISHED|CONNECTING|DELETING)`)
	espStateRe = regexp.MustCompile(`(?m)^\s*%?[\w.-]*-esp:\s+#\d+,\s+reqid.*?,\s+(INSTALLED|REKEYED)`)
	encRe      = regexp.MustCompile(`AES_[A-Z0-9_]+|CHACHA20_POLY1305`)
	dhRe       = regexp.MustCompile(`MODP_\d+|CURVE_\d+`)
)

// Status parses `swanctl --list-sas` text output. We deliberately avoid a
// vici client library (no external deps / no network for `go get`) and
// instead parse the human-readable CLI output, which is stable enough for
// status reporting purposes.
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
func EnsureRunning() error {
	out, err := run("systemctl", "is-active", "strongswan")
	if err == nil && strings.TrimSpace(out) == "active" {
		return nil
	}
	// Ubuntu 24.04 ships the swanctl-flavoured unit as strongswan.service
	// (strongswan-starter is the legacy ipsec.conf variant).
	_, err = run("systemctl", "start", "strongswan")
	return err
}

// psk length sanity used by `nosrat init` when generating a new PSK.
func ValidatePSKStrength(psk string) error {
	if len(psk) < 32 {
		return fmt.Errorf("PSK too short (%d bytes) - need >=32 bytes of entropy", len(psk))
	}
	return nil
}

func init() {
	// quiet the unused-import complaint on strconv if a build tag path
	// doesn't use it (kept for future numeric parsing of vici output).
	_ = strconv.Itoa
}
