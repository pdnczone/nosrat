# Nosrat — Production Audit Report

**Date:** 2026-09-07
**Auditor:** Agnes AI
**Repository:** https://github.com/pdnczone/nosrat
**Version:** Production Audit v1.0

---

## Executive Summary

Nosrat is a GRE-over-IPsec tunnel manager written in Go. The codebase is well-structured with clean separation of concerns across 7 internal packages. However, several critical issues were found:

- **CRITICAL:** Module path mismatch (`github.com/pdnc/grectl` vs `github.com/pdnczone/nosrat`)
- **CRITICAL:** Installer breaks when piped to bash (BASH_SOURCE issue)
- **HIGH:** Custom YAML parser has edge-case bugs
- **HIGH:** Firewall rules are overly permissive (policy accept)
- **MEDIUM:** systemd service has incorrect documentation URL
- **MEDIUM:** Missing input validation in several areas
- **LOW:** Dead code and unused imports

---

## 1. Architecture Overview

### Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                        CLI (main.go)                        │
│  init │ create │ start │ stop │ restart │ status │ health  │
│  routes │ ipsec │ logs │ diagnose │ uninstall │ run-daemon│
└──────────────────────────┬──────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
│   config     │  │    health    │  │   diagnostics    │
│  (yamllite)  │  │   (ping)     │  │   (checklist)    │
└──────────────┘  └──────────────┘  └──────────────────┘
        │
        ├──────────────┬──────────────┬──────────────┐
        ▼              ▼              ▼              ▼
┌──────────────┐┌──────────────┐┌──────────────┐┌──────────────┐
│     gre      ││    ipsec     ││   routing    ││  firewall    │
│  (ip tunnel) ││  (swanctl)   ││  (ip route)  ││  (nftables)  │
└──────────────┘└──────────────┘└──────────────┘└──────────────┘
```

### Lifecycle Flow

```
install.sh → init → create → start → [health loop] → stop → uninstall
```

---

## 2. Critical Bugs

### BUG-001: Module Path Mismatch (CRITICAL)

**File:** `go.mod`
**Problem:** Module is declared as `github.com/pdnc/grectl` but repository is `github.com/pdnczone/nosrat`
**Impact:** Cannot build, cannot import, breaks `go mod tidy`
**Fix:** Change to `github.com/pdnczone/nosrat` and update all imports

### BUG-002: Installer BASH_SOURCE Issue (CRITICAL)

**File:** `install.sh`
**Problem:** `SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` fails when script is piped to bash
**Impact:** `curl | bash` installation method is broken
**Fix:** Support both local and remote installation modes

### BUG-003: systemd Documentation URL Wrong (HIGH)

**File:** `systemd/nosrat.service`
**Problem:** `Documentation=https://github.com/purixa/GREoverIPSEC` — wrong URL
**Impact:** Incorrect documentation reference
**Fix:** Change to `https://github.com/pdnczone/nosrat`

---

## 3. High Severity Bugs

### BUG-004: YAML Parser Edge Cases (HIGH)

**File:** `internal/config/yamllite.go`
**Problems:**
1. `parseBlock(firstIndent + 1)` — assumes 1-space indent, but config uses 2-space
2. No support for multi-line values
3. No support for nested lists beyond simple mappings
4. `stripComment` doesn't handle `#` inside values properly

### BUG-005: Firewall Overly Permissive (HIGH)

**File:** `internal/firewall/firewall.go`
**Problem:** `policy accept` on both input and forward chains
**Impact:** If nosrat is the only firewall, it accepts everything
**Fix:** Use `policy drop` and explicitly allow only needed traffic

### BUG-006: Missing Route Validation (HIGH)

**File:** `internal/routing/routing.go`
**Problem:** No check that remote public IP route doesn't go through GRE tunnel
**Impact:** Can create routing loop where IPsec peer traffic goes through tunnel

---

## 4. Medium Severity Issues

### BUG-007: PSK Logged in Plaintext (MEDIUM)

**File:** `internal/ipsec/ipsec.go`
**Problem:** PSK is embedded in swanctl config file with `secret = "..."`
**Impact:** PSK visible in process args if logged

### BUG-008: No Timeout on External Commands (MEDIUM)

**Problem:** Many `exec.Command` calls have no timeout
**Impact:** Can hang indefinitely if network is unreachable

### BUG-009: Incomplete Uninstall (MEDIUM)

**File:** `cmd/nosrat/main.go`
**Problem:** `cmdUninstall` doesn't remove sysctl config or static routes
**Impact:** Stale configuration after uninstall

---

## 5. Low Severity Issues

### BUG-010: Dead Code (LOW)

**File:** `internal/ipsec/ipsec.go`
**Problem:** `strconv` import is unused (suppressed with `_ = strconv.Itoa`)

### BUG-011: Missing Error Handling (LOW)

**File:** Multiple files
**Problem:** Some errors are silently ignored with `_ = err`

---

## 6. Security Issues

| ID | Issue | Severity | File |
|----|-------|----------|------|
| SEC-001 | PSK in config file | HIGH | ipsec.go |
| SEC-002 | Firewall policy accept | HIGH | firewall.go |
| SEC-003 | No command injection protection | MEDIUM | multiple |
| SEC-004 | Installer doesn't verify checksums | MEDIUM | install.sh |
| SEC-005 | No rate limiting on health checks | LOW | health.go |

---

## 7. Reliability Issues

| ID | Issue | Severity |
|----|-------|----------|
| REL-001 | No timeout on ping commands | HIGH |
| REL-002 | No retry logic for IPsec initiation | MEDIUM |
| REL-003 | Health loop can thrash on flapping | MEDIUM |
| REL-004 | No backup/rollback on failed upgrade | LOW |

---

## 8. Installation Issues

| ID | Issue | Severity |
|----|-------|----------|
| INS-001 | BASH_SOURCE broken for pipe install | CRITICAL |
| INS-002 | No OS/version detection | HIGH |
| INS-003 | No architecture detection | MEDIUM |
| INS-004 | No dependency version validation | MEDIUM |
| INS-005 | No checksum verification | HIGH |

---

## 9. Networking Issues

| ID | Issue | Severity |
|----|-------|----------|
| NET-001 | No check for routing loop | HIGH |
| NET-002 | No IPv6 support | LOW |
| NET-003 | No MTU path discovery | MEDIUM |
| NET-004 | No NAT-T detection feedback | LOW |

---

## 10. Configuration Issues

| ID | Issue | Severity |
|----|-------|----------|
| CFG-001 | Custom YAML parser fragile | HIGH |
| CFG-002 | No config migration path | MEDIUM |
| CFG-003 | No config versioning | LOW |

---

## 11. Testing Gaps

- No unit tests for config parser
- No unit tests for GRE argument generation
- No unit tests for IPsec config generation
- No unit tests for firewall rule generation
- No integration tests
- No installer tests
- No mock command runners

---

## 12. Technical Debt

1. Custom YAML parser should be replaced with `gopkg.in/yaml.v3`
2. Command execution should be centralized with timeouts
3. Health check state machine is simplistic
4. Failover is configured but not implemented in code
5. No structured logging

---

## 13. Recommended Refactor Plan

### Phase 1: Module Identity
- Update `go.mod` to `github.com/pdnczone/nosrat`
- Update all internal imports
- Run `go mod tidy`

### Phase 2: Installer Rewrite
- Support both local and remote installation
- Add OS/architecture detection
- Add checksum verification
- Add rollback on failure

### Phase 3: Config Engine
- Replace custom YAML parser with `gopkg.in/yaml.v3`
- Add schema validation
- Add config versioning

### Phase 4: Security Hardening
- Fix firewall policies
- Remove PSK from config files
- Add command timeouts
- Add input validation

### Phase 5: Testing
- Unit tests for all packages
- Integration tests with network namespaces
- Installer tests

---

**Audit Completed By:** Agnes AI
**Next Review:** After Phase 1-5 implementation
