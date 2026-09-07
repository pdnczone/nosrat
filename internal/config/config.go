package config

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"os"
	"regexp"
	"strings"
)

// StaticRoute is a single routing entry pushed over the tunnel.
type StaticRoute struct {
	To     string `yaml:"to"`      // CIDR, e.g. "10.10.0.0/24"
	ViaGRE bool   `yaml:"via_gre"` // if true, next-hop is the GRE peer address
}

type Endpoint struct {
	PublicIP string `yaml:"public_ip"`
	GREIP    string `yaml:"gre_ip"` // CIDR, e.g. "10.200.0.1/30"
}

type IPsecConfig struct {
	IKEVersion   int    `yaml:"ike_version"`
	Mode         string `yaml:"mode"`       // "transport" (default) or "tunnel"
	Encryption   string `yaml:"encryption"` // e.g. aes256gcm16
	Integrity    string `yaml:"integrity"`  // only used for non-AEAD ciphers
	DHGroup      int    `yaml:"dh_group"`
	PSKFile      string `yaml:"psk_file"`
	RekeySeconds int    `yaml:"rekey_seconds"`
	DPDDelaySec  int    `yaml:"dpd_delay"`
	DPDTimeout   int    `yaml:"dpd_timeout"`
}

type RoutingConfig struct {
	Enabled      bool          `yaml:"enabled"`
	StaticRoutes []StaticRoute `yaml:"static_routes"`
}

type FirewallConfig struct {
	Enabled  bool `yaml:"enabled"`
	AllowSSH bool `yaml:"allow_ssh"`
}

type MTUConfig struct {
	Value    int  `yaml:"value"`
	MSSClamp bool `yaml:"mss_clamp"`
}

type KeepaliveConfig struct {
	Enabled  bool `yaml:"enabled"`
	Interval int  `yaml:"interval"`
}

type HealthConfig struct {
	IntervalSeconds    int     `yaml:"interval_seconds"`
	LatencyThresholdMs int     `yaml:"latency_threshold_ms"`
	LossThresholdPct   float64 `yaml:"loss_threshold_pct"`
	AutoRecover        bool    `yaml:"auto_recover"`
}

type FailoverConfig struct {
	Enabled             bool   `yaml:"enabled"`
	SecondaryPublicIP   string `yaml:"secondary_public_ip"`
	SwitchAfterFailures int    `yaml:"switch_after_failures"`
}

type Config struct {
	Path       string          `yaml:"-"`
	TunnelName string          `yaml:"tunnel.name"`
	Local      Endpoint        `yaml:"local"`
	Remote     Endpoint        `yaml:"remote"`
	IPsec      IPsecConfig     `yaml:"ipsec"`
	Routing    RoutingConfig   `yaml:"routing"`
	Firewall   FirewallConfig  `yaml:"firewall"`
	MTU        MTUConfig       `yaml:"mtu"`
	Keepalive  KeepaliveConfig `yaml:"keepalive"`
	Health     HealthConfig    `yaml:"health"`
	Failover   FailoverConfig  `yaml:"failover"`
}

// envOr returns the value of an environment variable or a default.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// Load reads and parses a nosrat YAML config file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}

	cfg, err := parseYAML(data)
	if err != nil {
		return nil, fmt.Errorf("parsing config %s: %w", path, err)
	}

	cfg.Path = path

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// parseYAML handles the subset of YAML that nosrat configs use.
// Supports: nested mappings via indentation, scalars, lists of scalars and maps, comments.
func parseYAML(data []byte) (*Config, error) {
	lines := strings.Split(string(data), "\n")

	type rawLine struct {
		indent int
		text   string
		lineNo int
	}

	var raw []rawLine
	for i, l := range lines {
		trimmedRight := strings.TrimRight(l, " \t\r")
		if strings.TrimSpace(trimmedRight) == "" {
			continue
		}
		content := stripComment(trimmedRight)
		if strings.TrimSpace(content) == "" {
			continue
		}
		indent := 0
		for indent < len(content) && content[indent] == ' ' {
			indent++
		}
		raw = append(raw, rawLine{indent: indent, text: content[indent:], lineNo: i + 1})
	}

	pos := 0

	var parseBlock func(minIndent int) (any, error)

	parseScalar := func(s string) any {
		s = strings.TrimSpace(s)
		if len(s) >= 2 && ((s[0] == '"' && s[len(s)-1] == '"') || (s[0] == '\'' && s[len(s)-1] == '\'')) {
			return s[1 : len(s)-1]
		}
		switch strings.ToLower(s) {
		case "true":
			return true
		case "false":
			return false
		case "null", "~", "":
			return nil
		}
		if i, err := parseInt(s); err == nil {
			return i
		}
		if f, err := parseFloat(s); err == nil {
			return f
		}
		return s
	}

	parseBlock = func(minIndent int) (any, error) {
		if pos >= len(raw) {
			return map[string]any{}, nil
		}

		firstIndent := raw[pos].indent
		if firstIndent < minIndent {
			return map[string]any{}, nil
		}

		if strings.HasPrefix(raw[pos].text, "- ") || raw[pos].text == "-" {
			var list []any
			for pos < len(raw) && raw[pos].indent == firstIndent &&
				(strings.HasPrefix(raw[pos].text, "- ") || raw[pos].text == "-") {
				itemText := strings.TrimPrefix(raw[pos].text, "-")
				itemText = strings.TrimPrefix(itemText, " ")
				lineNo := raw[pos].lineNo

				if strings.Contains(itemText, ":") && !isQuoted(itemText) {
					k, v, ok := splitKV(itemText)
					if !ok {
						return nil, fmt.Errorf("line %d: malformed list-map item %q", lineNo, itemText)
					}
					m := map[string]any{}
					if v == "" {
						pos++
						sub, err := parseBlock(firstIndent + 2)
						if err != nil {
							return nil, err
						}
						m[k] = sub
					} else {
						m[k] = parseScalar(v)
						pos++
					}
					for pos < len(raw) && raw[pos].indent > firstIndent {
						k2, v2, ok := splitKV(raw[pos].text)
						if !ok {
							return nil, fmt.Errorf("line %d: expected key: value", raw[pos].lineNo)
						}
						if v2 == "" {
							pos++
							sub, err := parseBlock(raw[pos-1].indent + 2)
							if err != nil {
								return nil, err
							}
							m[k2] = sub
						} else {
							m[k2] = parseScalar(v2)
							pos++
						}
					}
					list = append(list, m)
				} else if itemText == "" {
					pos++
					sub, err := parseBlock(firstIndent + 2)
					if err != nil {
						return nil, err
					}
					list = append(list, sub)
				} else {
					list = append(list, parseScalar(itemText))
					pos++
				}
			}
			return list, nil
		}

		m := map[string]any{}
		for pos < len(raw) && raw[pos].indent == firstIndent {
			k, v, ok := splitKV(raw[pos].text)
			if !ok {
				return nil, fmt.Errorf("line %d: expected 'key: value', got %q", raw[pos].lineNo, raw[pos].text)
			}
			pos++
			if v == "" {
				sub, err := parseBlock(firstIndent + 2)
				if err != nil {
					return nil, err
				}
				m[k] = sub
			} else {
				m[k] = parseScalar(v)
			}
		}
		return m, nil
	}

	result, err := parseBlock(0)
	if err != nil {
		return nil, err
	}

	cfg, ok := result.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("top-level document must be a mapping")
	}

	return mapToConfig(cfg)
}

// mapToConfig converts a generic map to a Config struct with defaults.
func mapToConfig(m map[string]any) (*Config, error) {
	cfg := &Config{
		TunnelName: getString(m, "tunnel.name", "nosrat"),
		Local: Endpoint{
			PublicIP: getString(m, "local.public_ip", ""),
			GREIP:    getString(m, "local.gre_ip", ""),
		},
		Remote: Endpoint{
			PublicIP: getString(m, "remote.public_ip", ""),
			GREIP:    getString(m, "remote.gre_ip", ""),
		},
		IPsec: IPsecConfig{
			IKEVersion:   getInt(m, "ipsec.ike_version", 2),
			Mode:         getString(m, "ipsec.mode", "transport"),
			Encryption:   getString(m, "ipsec.encryption", "aes256gcm16"),
			Integrity:    getString(m, "ipsec.integrity", ""),
			DHGroup:      getInt(m, "ipsec.dh_group", 14),
			PSKFile:      getString(m, "ipsec.psk_file", "/etc/nosrat/secrets/psk"),
			RekeySeconds: getInt(m, "ipsec.rekey_seconds", 3600),
			DPDDelaySec:  getInt(m, "ipsec.dpd_delay", 10),
			DPDTimeout:   getInt(m, "ipsec.dpd_timeout", 30),
		},
		Routing: RoutingConfig{
			Enabled: getBool(m, "routing.enabled", true),
		},
		Firewall: FirewallConfig{
			Enabled:  getBool(m, "firewall.enabled", true),
			AllowSSH: getBool(m, "firewall.allow_ssh", true),
		},
		MTU: MTUConfig{
			Value:    getInt(m, "mtu.value", 1400),
			MSSClamp: getBool(m, "mtu.mss_clamp", true),
		},
		Keepalive: KeepaliveConfig{
			Enabled:  getBool(m, "keepalive.enabled", true),
			Interval: getInt(m, "keepalive.interval", 10),
		},
		Health: HealthConfig{
			IntervalSeconds:    getInt(m, "health.interval_seconds", 15),
			LatencyThresholdMs: getInt(m, "health.latency_threshold_ms", 200),
			LossThresholdPct:   getFloat(m, "health.loss_threshold_pct", 5),
			AutoRecover:        getBool(m, "health.auto_recover", true),
		},
		Failover: FailoverConfig{
			Enabled:             getBool(m, "failover.enabled", false),
			SecondaryPublicIP:   getString(m, "failover.secondary_public_ip", ""),
			SwitchAfterFailures: getInt(m, "failover.switch_after_failures", 3),
		},
	}

	// Parse static routes
	for _, item := range getList(m, "routing.static_routes") {
		if rm, ok := item.(map[string]any); ok {
			cfg.Routing.StaticRoutes = append(cfg.Routing.StaticRoutes, StaticRoute{
				To:     getStringNested(rm, "to", ""),
				ViaGRE: getBoolNested(rm, "via_gre", true),
			})
		}
	}

	return cfg, nil
}

// Validate checks required fields and semantic constraints.
func (c *Config) Validate() error {
	var errs []string

	if c.TunnelName == "" {
		errs = append(errs, "tunnel.name is required")
	}

	// Validate tunnel name (alphanumeric, hyphen, underscore)
	if matched, _ := regexp.MatchString(`^[a-zA-Z0-9_-]+$`, c.TunnelName); !matched {
		errs = append(errs, "tunnel.name must contain only alphanumeric characters, hyphens, and underscores")
	}

	if net.ParseIP(c.Local.PublicIP) == nil {
		errs = append(errs, fmt.Sprintf("local.public_ip: invalid IP address %q", c.Local.PublicIP))
	}

	if net.ParseIP(c.Remote.PublicIP) == nil {
		errs = append(errs, fmt.Sprintf("remote.public_ip: invalid IP address %q", c.Remote.PublicIP))
	}

	if _, _, err := net.ParseCIDR(c.Local.GREIP); err != nil {
		errs = append(errs, fmt.Sprintf("local.gre_ip: invalid CIDR %q (expected format: 10.200.0.1/30)", c.Local.GREIP))
	}

	if _, _, err := net.ParseCIDR(c.Remote.GREIP); err != nil {
		errs = append(errs, fmt.Sprintf("remote.gre_ip: invalid CIDR %q (expected format: 10.200.0.2/30)", c.Remote.GREIP))
	}

	if c.IPsec.IKEVersion != 2 {
		errs = append(errs, "ipsec.ike_version: only IKEv2 is supported (IKEv1 is deprecated)")
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
		errs = append(errs, fmt.Sprintf("ipsec.psk_file (%s) does not exist - run 'nosrat init' first", c.IPsec.PSKFile))
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
func (c *Config) MSSValue() int {
	return c.MTU.Value - 40
}

// ReadPSK loads the pre-shared key from the configured secret file.
func (c *Config) ReadPSK() (string, error) {
	return ReadPSKFromFile(c.IPsec.PSKFile)
}

// ReadPSKFromFile loads a PSK from a file with strict permission checks.
func ReadPSKFromFile(path string) (string, error) {
	fi, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("psk_file: %w", err)
	}

	if fi.Mode().Perm()&0077 != 0 {
		return "", fmt.Errorf("psk_file %s has insecure permissions %v (expected 0600)", path, fi.Mode().Perm())
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(data)), nil
}

// GeneratePSK creates a new cryptographically secure PSK.
func GeneratePSK() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generating PSK: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// ValidatePSKStrength checks if a PSK has sufficient entropy.
func ValidatePSKStrength(psk string) error {
	if len(psk) < 32 {
		return fmt.Errorf("PSK too short (%d bytes) - need >=32 bytes of entropy", len(psk))
	}
	return nil
}

// LocalGREAddr / RemoteGREAddr strip the CIDR mask, returning bare IPs.
func (c *Config) LocalGREAddr() string  { return stripMask(c.Local.GREIP) }
func (c *Config) RemoteGREAddr() string { return stripMask(c.Remote.GREIP) }

func stripMask(cidr string) string {
	ip, _, err := net.ParseCIDR(cidr)
	if err != nil {
		return cidr
	}
	return ip.String()
}

// Save writes the config to a file with safe permissions.
func (c *Config) Save(path string) error {
	data, err := c.MarshalYAML()
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

// MarshalYAML serializes the config to YAML format.
func (c *Config) MarshalYAML() ([]byte, error) {
	var sb strings.Builder

	fmt.Fprintf(&sb, "tunnel:\n  name: %s\n\n", c.TunnelName)

	fmt.Fprintf(&sb, "local:\n  public_ip: \"%s\"\n  gre_ip: \"%s\"\n\n", c.Local.PublicIP, c.Local.GREIP)
	fmt.Fprintf(&sb, "remote:\n  public_ip: \"%s\"\n  gre_ip: \"%s\"\n\n", c.Remote.PublicIP, c.Remote.GREIP)

	fmt.Fprintf(&sb, "ipsec:\n")
	fmt.Fprintf(&sb, "  ike_version: %d\n", c.IPsec.IKEVersion)
	fmt.Fprintf(&sb, "  mode: %s\n", c.IPsec.Mode)
	fmt.Fprintf(&sb, "  encryption: %s\n", c.IPsec.Encryption)
	if c.IPsec.Integrity != "" {
		fmt.Fprintf(&sb, "  integrity: %s\n", c.IPsec.Integrity)
	}
	fmt.Fprintf(&sb, "  dh_group: %d\n", c.IPsec.DHGroup)
	fmt.Fprintf(&sb, "  psk_file: %s\n", c.IPsec.PSKFile)
	fmt.Fprintf(&sb, "  rekey_seconds: %d\n", c.IPsec.RekeySeconds)
	fmt.Fprintf(&sb, "  dpd_delay: %d\n", c.IPsec.DPDDelaySec)
	fmt.Fprintf(&sb, "  dpd_timeout: %d\n\n", c.IPsec.DPDTimeout)

	fmt.Fprintf(&sb, "routing:\n  enabled: %t\n", c.Routing.Enabled)
	if len(c.Routing.StaticRoutes) > 0 {
		fmt.Fprintf(&sb, "  static_routes:\n")
		for _, r := range c.Routing.StaticRoutes {
			fmt.Fprintf(&sb, "    - to: %s\n", r.To)
			fmt.Fprintf(&sb, "      via_gre: %t\n", r.ViaGRE)
		}
	}
	fmt.Fprintf(&sb, "\n")

	fmt.Fprintf(&sb, "firewall:\n  enabled: %t\n  allow_ssh: %t\n\n", c.Firewall.Enabled, c.Firewall.AllowSSH)

	fmt.Fprintf(&sb, "mtu:\n  value: %d\n  mss_clamp: %t\n\n", c.MTU.Value, c.MTU.MSSClamp)

	fmt.Fprintf(&sb, "keepalive:\n  enabled: %t\n  interval: %d\n\n", c.Keepalive.Enabled, c.Keepalive.Interval)

	fmt.Fprintf(&sb, "health:\n  interval_seconds: %d\n  latency_threshold_ms: %d\n  loss_threshold_pct: %g\n  auto_recover: %t\n\n",
		c.Health.IntervalSeconds, c.Health.LatencyThresholdMs, c.Health.LossThresholdPct, c.Health.AutoRecover)

	fmt.Fprintf(&sb, "failover:\n  enabled: %t\n  secondary_public_ip: \"%s\"\n  switch_after_failures: %d\n",
		c.Failover.Enabled, c.Failover.SecondaryPublicIP, c.Failover.SwitchAfterFailures)

	return []byte(sb.String()), nil
}

// ── Helper functions for map access ───────────────────────────────────────

func getString(m map[string]any, key, def string) string {
	parts := strings.Split(key, ".")
	current := m

	for i, part := range parts {
		if i == len(parts)-1 {
			if v, ok := current[part]; ok && v != nil {
				return fmt.Sprintf("%v", v)
			}
			return def
		}
		if next, ok := current[part]; ok {
			if nextMap, ok := next.(map[string]any); ok {
				current = nextMap
			} else {
				return def
			}
		} else {
			return def
		}
	}
	return def
}

func getInt(m map[string]any, key string, def int) int {
	parts := strings.Split(key, ".")
	current := m

	for i, part := range parts {
		if i == len(parts)-1 {
			if v, ok := current[part]; ok {
				switch t := v.(type) {
				case int:
					return t
				case float64:
					return int(t)
				case string:
					if i, err := parseInt(t); err == nil {
						return i
					}
				}
			}
			return def
		}
		if next, ok := current[part]; ok {
			if nextMap, ok := next.(map[string]any); ok {
				current = nextMap
			} else {
				return def
			}
		} else {
			return def
		}
	}
	return def
}

func getBool(m map[string]any, key string, def bool) bool {
	parts := strings.Split(key, ".")
	current := m

	for i, part := range parts {
		if i == len(parts)-1 {
			if v, ok := current[part]; ok {
				switch t := v.(type) {
				case bool:
					return t
				case string:
					if b, err := strconvParseBool(t); err == nil {
						return b
					}
				}
			}
			return def
		}
		if next, ok := current[part]; ok {
			if nextMap, ok := next.(map[string]any); ok {
				current = nextMap
			} else {
				return def
			}
		} else {
			return def
		}
	}
	return def
}

func getFloat(m map[string]any, key string, def float64) float64 {
	parts := strings.Split(key, ".")
	current := m

	for i, part := range parts {
		if i == len(parts)-1 {
			if v, ok := current[part]; ok {
				switch t := v.(type) {
				case float64:
					return t
				case int:
					return float64(t)
				case string:
					if f, err := parseFloat(t); err == nil {
						return f
					}
				}
			}
			return def
		}
		if next, ok := current[part]; ok {
			if nextMap, ok := next.(map[string]any); ok {
				current = nextMap
			} else {
				return def
			}
		} else {
			return def
		}
	}
	return def
}

func getList(m map[string]any, key string) []any {
	parts := strings.Split(key, ".")
	current := m

	for i, part := range parts {
		if i == len(parts)-1 {
			if v, ok := current[part]; ok {
				if l, ok := v.([]any); ok {
					return l
				}
			}
			return nil
		}
		if next, ok := current[part]; ok {
			if nextMap, ok := next.(map[string]any); ok {
				current = nextMap
			} else {
				return nil
			}
		} else {
			return nil
		}
	}
	return nil
}

// ── Additional helpers ────────────────────────────────────────────────────

func getStringNested(m map[string]any, key, def string) string {
	if v, ok := m[key]; ok && v != nil {
		return fmt.Sprintf("%v", v)
	}
	return def
}

func getBoolNested(m map[string]any, key string, def bool) bool {
	if v, ok := m[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return def
}

func parseInt(s string) (int, error) {
	var i int
	_, err := fmt.Sscanf(s, "%d", &i)
	return i, err
}

func parseFloat(s string) (float64, error) {
	var f float64
	_, err := fmt.Sscanf(s, "%f", &f)
	return f, err
}

func strconvParseBool(s string) (bool, error) {
	switch strings.ToLower(s) {
	case "true", "yes", "1":
		return true, nil
	case "false", "no", "0":
		return false, nil
	}
	return false, fmt.Errorf("not a bool")
}

// ── YAML parsing helpers ──────────────────────────────────────────────────

func isQuoted(s string) bool {
	s = strings.TrimSpace(s)
	return len(s) >= 2 && (s[0] == '"' || s[0] == '\'')
}

func stripComment(s string) string {
	inQuote := byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inQuote != 0 {
			if c == inQuote {
				inQuote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			inQuote = c
			continue
		}
		if c == '#' {
			return s[:i]
		}
	}
	return s
}

func splitKV(s string) (key, val string, ok bool) {
	idx := -1
	inQuote := byte(0)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inQuote != 0 {
			if c == inQuote {
				inQuote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			inQuote = c
			continue
		}
		if c == ':' && (i+1 == len(s) || s[i+1] == ' ') {
			idx = i
			break
		}
	}
	if idx == -1 {
		return "", "", false
	}
	key = strings.TrimSpace(s[:idx])
	val = strings.TrimSpace(s[idx+1:])
	return key, val, true
}

// EnsureConfigDir creates the config directory structure.
func EnsureConfigDir() error {
	if err := os.MkdirAll("/etc/nosrat/secrets", 0700); err != nil {
		return err
	}
	return os.Chmod("/etc/nosrat/secrets", 0700)
}

// GetDefaultConfigPath returns the default configuration file path.
func GetDefaultConfigPath() string {
	return "/etc/nosrat/tunnel.yaml"
}

// GetDefaultPSKPath returns the default PSK file path.
func GetDefaultPSKPath() string {
	return "/etc/nosrat/secrets/psk"
}
