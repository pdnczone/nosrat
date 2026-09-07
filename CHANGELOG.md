# Changelog

All notable changes to nosrat will be documented in this file.

## [2.0.0] - 2026-09-07

### Production-Grade Refactor

Phase 0: Repository audit completed (13+ bugs identified)
Phase 1: Module path fixed (`github.com/pdnc/grectl` → `github.com/pdnczone/nosrat`)
Phase 2: Installer rewritten to support both local and remote (curl|bash) installation
Phase 3-4: Custom YAML parser replaced with proper schema validation
Phase 5-8: Security hardening (firewall policy drop, PSK handling)
Phase 9: Routing engine cleanup with route loop prevention
Phase 10: Health state machine (UP/DOWN/DEGRADED/FAILING/RECOVERING)
Phase 11: Failover state machine implementation
Phase 12: systemd service documentation fix
Phase 13-14: Main.go refactor (proper init flow, complete uninstall)
Phase 15: Centralized command execution with timeouts
Phase 16: Test suite added (config tests, validation, PSK)

### Added
- `internal/config/config.go` - Centralized config with validation
- `internal/cmd/runner.go` - Command runner with timeouts
- `internal/failover/failover.go` - Failover state machine
- `internal/health/health.go` - TunnelState enum
- `AUDIT.md` - Full repository audit report
- `SECURITY_AUDIT.md` - Security audit findings
- Unit tests for config parser and validation

### Changed
- Module path: `github.com/pdnc/grectl` → `github.com/pdnczone/nosrat`
- Firewall: policy accept → policy drop
- systemd: Documentation URL fixed
- PSK: Now uses crypto/rand with 32 bytes
- Config validation: Clear, actionable error messages

### Removed
- Unused `strconv` import in ipsec.go
- Unused `time` import in routing.go
- Dead code and verbose comments
- Custom YAML parser (replaced with proper validation)

### Security
- All secrets in environment or 0600 files
- No secrets in logs
- SQL injection: N/A (no database)
- Command injection: Verified safe (no shell expansion)
- Path traversal: Verified safe (scoped paths)
- Firewall: Now defaults to drop, only explicitly allowed traffic

## [1.0.0] - 2026-09-05

### Initial Release
- GRE-over-IPsec tunnel manager
- strongSwan integration
- nftables firewall
- Health monitoring
- systemd service
- Configuration via YAML
