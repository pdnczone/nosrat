package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseYAMLLite(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{
			name: "valid simple config",
			input: `
tunnel:
  name: test
local:
  public_ip: 1.2.3.4
  gre_ip: 10.0.0.1/30
remote:
  public_ip: 5.6.7.8
  gre_ip: 10.0.0.2/30
`,
			wantErr: false,
		},
		{
			name: "valid with comments",
			input: `
# This is a comment
tunnel:
  name: test # inline comment
local:
  public_ip: 1.2.3.4
`,
			wantErr: false,
		},
		{
			name: "empty document",
			input: `
`,
			wantErr: false,
		},
		{
			name: "list items",
			input: `
routing:
  static_routes:
    - to: 10.10.0.0/24
      via_gre: true
    - to: 10.20.0.0/24
      via_gre: false
`,
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := parseYAML([]byte(tt.input))
			if (err != nil) != tt.wantErr {
				t.Errorf("parseYAML() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && result == nil {
				t.Error("parseYAML() returned nil result")
			}
		})
	}
}

func TestConfigValidate(t *testing.T) {
	// Create a temporary PSK file for testing
	tmpDir := t.TempDir()
	pskFile := filepath.Join(tmpDir, "psk")
	if err := os.WriteFile(pskFile, []byte("test-psk-key-that-is-long-enough-for-validation"), 0600); err != nil {
		t.Fatalf("Failed to create temp PSK file: %v", err)
	}

	tests := []struct {
		name    string
		config  *Config
		wantErr bool
	}{
		{
			name: "valid config",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: false,
		},
		{
			name: "invalid tunnel name",
			config: &Config{
				TunnelName: "",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: true,
		},
		{
			name: "invalid IP",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "not-an-ip",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: true,
		},
		{
			name: "invalid CIDR",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "not-a-cidr",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: true,
		},
		{
			name: "weak DH group",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    5, // Weak!
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: true,
		},
		{
			name: "invalid MTU",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    pskFile,
				},
				MTU: MTUConfig{
					Value: 100, // Too small
				},
			},
			wantErr: true,
		},
		{
			name: "PSK file not found",
			config: &Config{
				TunnelName: "test",
				Local: Endpoint{
					PublicIP: "1.2.3.4",
					GREIP:    "10.0.0.1/30",
				},
				Remote: Endpoint{
					PublicIP: "5.6.7.8",
					GREIP:    "10.0.0.2/30",
				},
				IPsec: IPsecConfig{
					IKEVersion: 2,
					Mode:       "transport",
					Encryption: "aes256gcm16",
					DHGroup:    14,
					PSKFile:    "/nonexistent/path/psk",
				},
				MTU: MTUConfig{
					Value: 1400,
				},
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestGeneratePSK(t *testing.T) {
	psk, err := GeneratePSK()
	if err != nil {
		t.Fatalf("GeneratePSK() error = %v", err)
	}

	if len(psk) < 32 {
		t.Errorf("GeneratePSK() returned short PSK: %d chars", len(psk))
	}

	// Should be base64 encoded (no padding)
	if strings.Contains(psk, "=") {
		t.Error("GeneratePSK() should use RawURLEncoding (no padding)")
	}
}

func TestValidatePSKStrength(t *testing.T) {
	tests := []struct {
		name    string
		psk     string
		wantErr bool
	}{
		{
			name:    "valid PSK",
			psk:     "abcdefghijklmnopqrstuvwxyz1234567890",
			wantErr: false,
		},
		{
			name:    "short PSK",
			psk:     "short",
			wantErr: true,
		},
		{
			name:    "empty PSK",
			psk:     "",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePSKStrength(tt.psk)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidatePSKStrength() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestMSSValue(t *testing.T) {
	c := &Config{
		MTU: MTUConfig{
			Value: 1400,
		},
	}

	expected := 1360
	if got := c.MSSValue(); got != expected {
		t.Errorf("MSSValue() = %d, want %d", got, expected)
	}
}

func TestStripMask(t *testing.T) {
	tests := []struct {
		cidr     string
		expected string
	}{
		{"10.0.0.1/30", "10.0.0.1"},
		{"192.168.1.1/24", "192.168.1.1"},
		{"invalid", "invalid"},
		{"", ""},
	}

	for _, tt := range tests {
		t.Run(tt.cidr, func(t *testing.T) {
			got := stripMask(tt.cidr)
			if got != tt.expected {
				t.Errorf("stripMask(%q) = %q, want %q", tt.cidr, got, tt.expected)
			}
		})
	}
}
