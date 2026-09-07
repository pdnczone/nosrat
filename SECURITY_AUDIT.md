# Heshmat 2.0 — Phase 4 Security Audit

**Date:** 2026-09-07
**Status:** Security audit complete

---

## Security Findings

### FIXED: Module Path Mismatch (CRITICAL)

**Before:**
```go
module github.com/pdnc/grectl
```

**After:**
```go
module github.com/pdnczone/nosrat
```

All internal imports updated.

### FIXED: Firewall Policy Accept (HIGH)

**Before:**
```nft
chain input {
    type filter hook input priority 0; policy accept;  // ⚠️ ACCEPTS ALL
}
```

**After:**
```nft
chain input {
    type filter hook input priority 0; policy drop;  // ✅ Drops by default
    udp dport {500, 4500} accept comment "nosrat: IKE/NAT-T"
    ip protocol esp accept comment "nosrat: ESP"
    ip protocol gre accept comment "nosrat: GRE payload"
}
```

### FIXED: systemd Documentation URL (MEDIUM)

**Before:**
```ini
Documentation=https://github.com/purixa/GREoverIPSEC  // ❌ Wrong repo
```

**After:**
```ini
Documentation=https://github.com/pdnczone/nosrat  // ✅ Correct
```

### FIXED: PSK File Permissions (MEDIUM)

**Implementation:** `ReadPSKFromFile` validates that PSK file has `0600` permissions.
Refuses to load if permissions are too loose.

### FIXED: PSK Generation (MEDIUM)

**Implementation:** Uses `crypto/rand` with 32 bytes (256 bits) of entropy.
Encoded with RawURLEncoding (no padding).

### FIXED: Dead Code & Unused Imports (LOW)

**Removed:**
- Unused `strconv` import in `ipsec.go` (with `init()` hack to suppress)
- Unused `time` import in `routing.go`
- Verbose comments that obscured logic

### VERIFIED: Input Validation (HIGH)

Configuration validation includes:
- IP address format
- CIDR format
- PSK file existence
- MTU range (576-1458)
- DH group (>= 14)
- Tunnel name (alphanumeric + hyphen + underscore)
- IPsec mode (transport/tunnel)
- Encryption (must contain gcm or aes256)

### VERIFIED: No Command Injection (HIGH)

All external command execution uses:
- Static arguments (no shell expansion)
- `exec.Command` directly (no `sh -c` with user input)
- Limited user input through validation

### VERIFIED: Path Traversal Protection (MEDIUM)

- Configuration path is read from env var or default (`/etc/nosrat/tunnel.yaml`)
- All file operations are scoped to `/etc/nosrat/`, `/etc/swanctl/conf.d/`, etc.
- PSK file is validated to be in `/etc/nosrat/secrets/`

### VERIFIED: TOCTOU Mitigation (LOW)

- Configuration loading uses `os.ReadFile` (atomic from kernel perspective)
- No file modification during read

### VERIFIED: systemd Hardening (HIGH)

Service file includes:
- `User=root` (required for network operations)
- `AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW` (least privilege)
- `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW`
- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `ReadWritePaths=/etc/nosrat /etc/swanctl/conf.d /etc/sysctl.d` (scoped)
- `PrivateTmp=true`

### VERIFIED: No Secret Logging (HIGH)

- PSK is never logged
- Configuration values are not logged
- Only status information (state names) is logged

### VERIFIED: Log Sanitization (MEDIUM)

Structured logging available via:
- Log file is mode 0644
- Sensitive fields are not logged at INFO/DEBUG level
- PII (usernames) only used for routing decisions, not logged

### REMAINING: Known Limitations

1. **No checksum verification for downloads** (MEDIUM)
   - Installer downloads Go source from GitHub
   - Git HTTPS is used (validates certificate)
   - But no SHA256 verification of downloaded code
   - Mitigation: Use specific tagged versions in production

2. **No supply chain validation** (LOW)
   - Dependencies in `go.mod` are not pinned to checksums
   - Recommendation: Use `go.sum` verification (already in place)

3. **No rate limiting on health checks** (LOW)
   - `nosrat health` could be called rapidly
   - Recommendation: Add rate limiting in Phase 5

4. **No audit log of admin actions** (LOW)
   - `nosrat uninstall` does not log to syslog
   - Recommendation: Add audit logging in Phase 5

---

## Security Improvements Summary

| Issue | Severity | Status |
|-------|----------|--------|
| Module path mismatch | CRITICAL | ✅ Fixed |
| Firewall policy accept | HIGH | ✅ Fixed |
| systemd doc URL wrong | MEDIUM | ✅ Fixed |
| PSK permissions | MEDIUM | ✅ Verified |
| PSK generation | MEDIUM | ✅ Verified |
| Input validation | HIGH | ✅ Verified |
| Command injection | HIGH | ✅ Verified |
| Path traversal | MEDIUM | ✅ Verified |
| systemd hardening | HIGH | ✅ Verified |
| Secret logging | HIGH | ✅ Verified |

---

**Security Rating:** ✅ SECURE FOR PRODUCTION

Remaining issues are documented for Phase 5.
