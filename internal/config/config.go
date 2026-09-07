package config

import (
	"fmt"
	"net"
	"os"
	"strings"
)

// StaticRoute is a single routing entry pushed over the tunnel.
type StaticRoute struct {
	To     string // CIDR, e.g. "10.10.0.0/24"
	ViaGRE bool   // if true, next-hop is the GRE peer address (via the GRE interface)
}

type Endpoint struct {
	PublicIP string
	GREIP    string // CIDR, e.g. "10.200.0.1/30"
}

type IPsecConfig struct {
	IKEVersion   int
	Mode         string // "transport" (default) or "tunnel"
	Encryption   string // e.g. aes256gcm16
	Integrity    string // only used for non-AEAD ciphers; ignored for *gcm* ciphers
	DHGroup      int
	PSKFile      string
	RekeySeconds int
	DPDDelaySec  int
	DPDTimeout   int
}

type RoutingConfig struct {
	Enabled      bool
	StaticRoutes []StaticRoute
}

type FirewallConfig struct {
	Enabled  bool
	AllowSSH bool
}

type MTUConfig struct {
	Value    int
	MSSClamp bool
}

type KeepaliveConfig struct {
	Enabled  bool
	Interval int
}

type HealthConfig struct {
	IntervalSeconds    int
	LatencyThresholdMs int
	LossThresholdPct   float64
	AutoRecover        bool
}

type FailoverConfig struct {
	Enabled             bool
	SecondaryPublicIP   string
	SwitchAfterFailures int
}

type Config struct {
	Path string

	TunnelName string

	Local  Endpoint
	Remote Endpoint

	IPsec     IPsecConfig
	Routing   RoutingConfig
	Firewall  FirewallConfig
	MTU       MTUConfig
	Keepalive KeepaliveConfig
	Health    HealthConfig
	Failover  FailoverConfig
}

// Load reads and parses a nosrat YAML config file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}
	root, err := parseYAMLLite(data)
	if err != nil {
		return nil, fmt.Errorf("parsing config %s: %w", path, err)
	}

	tunnel := getMap(root, "tunnel")
	local := getMap(root, "local")
	remote := getMap(root, "remote")
	ipsecM := getMap(root, "ipsec")
	routingM := getMap(root, "routing")
	firewallM := getMap(root, "firewall")
	mtuM := getMap(root, "mtu")
	keepaliveM := getMap(root, "keepalive")
	healthM := getMap(root, "health")
	failoverM := getMap(root, "failover")

	var routes []StaticRoute
	for _, item := range getList(routingM, "static_routes") {
		rm, ok := item.(map[string]any)
		if !ok {
			continue
		}
		routes = append(routes, StaticRoute{
			To:     getString(rm, "to", ""),
			ViaGRE: getBool(rm, "via_gre", true),
		})
	}

	cfg := &Config{
		Path:       path,
		TunnelName: getString(tunnel, "name", "nosrat"),
		Local: Endpoint{
			PublicIP: getString(local, "public_ip", ""),
			GREIP:    getString(local, "gre_ip", ""),
		},
		Remote: Endpoint{
			PublicIP: getString(remote, "public_ip", ""),
			GREIP:    getString(remote, "gre_ip", ""),
		},
		IPsec: IPsecConfig{
			IKEVersion:   getInt(ipsecM, "ike_version", 2),
			Mode:         getString(ipsecM, "mode", "transport"),
			Encryption:   getString(ipsecM, "encryption", "aes256gcm16"),
			Integrity:    getString(ipsecM, "integrity", ""),
			DHGroup:      getInt(ipsecM, "dh_group", 14),
			PSKFile:      getString(ipsecM, "psk_file", "/etc/nosrat/secrets/psk"),
			RekeySeconds: getInt(ipsecM, "rekey_seconds", 3600),
			DPDDelaySec:  getInt(ipsecM, "dpd_delay", 10),
			DPDTimeout:   getInt(ipsecM, "dpd_timeout", 30),
		},
		Routing: RoutingConfig{
			Enabled:      getBool(routingM, "enabled", true),
			StaticRoutes: routes,
		},
		Firewall: FirewallConfig{
			Enabled:  getBool(firewallM, "enabled", true),
			AllowSSH: getBool(firewallM, "allow_ssh", true),
		},
		MTU: MTUConfig{
			Value:    getInt(mtuM, "value", 1400),
			MSSClamp: getBool(mtuM, "mss_clamp", true),
		},
		Keepalive: KeepaliveConfig{
			Enabled:  getBool(keepaliveM, "enabled", true),
			Interval: getInt(keepaliveM, "interval", 10),
		},
		Health: HealthConfig{
			IntervalSeconds:    getInt(healthM, "interval_seconds", 15),
			LatencyThresholdMs: getInt(healthM, "latency_threshold_ms", 200),
			LossThresholdPct:   floatOr(healthM, "loss_threshold_pct", 5),
			AutoRecover:        getBool(healthM, "auto_recover", true),
		},
		Failover: FailoverConfig{
			Enabled:             getBool(failoverM, "enabled", false),
			SecondaryPublicIP:   getString(failoverM, "secondary_public_ip", ""),
			SwitchAfterFailures: getInt(failoverM, "switch_after_failures", 3),
		},
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func floatOr(m map[string]any, key string, def float64) float64 {
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case float64:
			return t
		case int:
			return float64(t)
		}
	}
	return def
}

// Validate checks required fields and semantic constraints. It intentionally
// fails loudly and early: a half-valid tunnel config brought up on a
// production VPS is worse than a config that refuses to load.
func (c *Config) Validate() error {
	var errs []string

	if c.TunnelName == "" {
		errs = append(errs, "tunnel.name is required")
	}
	if net.ParseIP(c.Local.PublicIP) == nil {
		errs = append(errs, "local.public_ip must be a valid IP")
	}
	if net.ParseIP(c.Remote.PublicIP) == nil {
		errs = append(errs, "remote.public_ip must be a valid IP")
	}
	if _, _, err := net.ParseCIDR(c.Local.GREIP); err != nil {
		errs = append(errs, "local.gre_ip must be CIDR, e.g. 10.200.0.1/30")
	}
	if _, _, err := net.ParseCIDR(c.Remote.GREIP); err != nil {
		errs = append(errs, "remote.gre_ip must be CIDR, e.g. 10.200.0.2/30")
	}
	if c.IPsec.IKEVersion != 2 {
		errs = append(errs, "ipsec.ike_version: only IKEv2 is supported (IKEv1 is deprecated/insecure)")
	}
	mode := strings.ToLower(c.IPsec.Mode)
	if mode != "transport" && mode != "tunnel" {
		errs = append(errs, "ipsec.mode must be 'transport' or 'tunnel'")
	}
	if !strings.Contains(strings.ToLower(c.IPsec.Encryption), "gcm") &&
		!strings.Contains(strings.ToLower(c.IPsec.Encryption), "aes256") {
		errs = append(errs, "ipsec.encryption: only modern AEAD/AES-256 ciphers are allowed (e.g. aes256gcm16)")
	}
	if c.IPsec.DHGroup < 14 {
		errs = append(errs, "ipsec.dh_group: must be >= 14 (MODP2048); groups 1/2/5 are weak and rejected")
	}
	if c.MTU.Value < 576 || c.MTU.Value > 1458 {
		errs = append(errs, "mtu.value: must be between 576 and 1458 for a GRE-over-IPsec(transport) tunnel on a 1500-MTU uplink")
	}
	if _, err := os.Stat(c.IPsec.PSKFile); err != nil {
		errs = append(errs, fmt.Sprintf("ipsec.psk_file (%s) does not exist yet - run 'nosrat init' first", c.IPsec.PSKFile))
	}
	for _, r := range c.Routing.StaticRoutes {
		if _, _, err := net.ParseCIDR(r.To); err != nil {
			errs = append(errs, fmt.Sprintf("routing.static_routes: %q is not a valid CIDR", r.To))
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("invalid configuration:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return nil
}

// MSSValue returns the TCP MSS to clamp to, given the tunnel MTU.
// MTU - 20 (IPv4) - 20 (TCP) = MSS. We do not assume IPv6 inner traffic here;
// if the inner network is IPv6-only, clamp separately to MTU-60.
func (c *Config) MSSValue() int {
	return c.MTU.Value - 40
}

// ReadPSK loads the pre-shared key from the configured secret file. The file
// must be root-owned, mode 0600 - LoadAndCheckPerms enforces that.
func (c *Config) ReadPSK() (string, error) {
	fi, err := os.Stat(c.IPsec.PSKFile)
	if err != nil {
		return "", fmt.Errorf("psk_file: %w", err)
	}
	if fi.Mode().Perm()&0077 != 0 {
		return "", fmt.Errorf("psk_file %s has insecure permissions %v (expected 0600)", c.IPsec.PSKFile, fi.Mode().Perm())
	}
	data, err := os.ReadFile(c.IPsec.PSKFile)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

// LocalGREAddr / RemoteGREAddr strip the CIDR mask, returning bare IPs -
// useful for building `ip route` next-hops.
func (c *Config) LocalGREAddr() string  { return stripMask(c.Local.GREIP) }
func (c *Config) RemoteGREAddr() string { return stripMask(c.Remote.GREIP) }

func stripMask(cidr string) string {
	ip, _, err := net.ParseCIDR(cidr)
	if err != nil {
		return cidr
	}
	return ip.String()
}
