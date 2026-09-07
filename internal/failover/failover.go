// Package failover implements automatic failover to a secondary peer
// when the primary tunnel becomes unhealthy.
package failover

import (
	"fmt"
	"sync"
	"time"

	"github.com/pdnczone/nosrat/internal/config"
	"github.com/pdnczone/nosrat/internal/gre"
	"github.com/pdnczone/nosrat/internal/health"
	"github.com/pdnczone/nosrat/internal/ipsec"
	"github.com/pdnczone/nosrat/internal/routing"
)

// State represents the current failover state
type State int

const (
	StatePrimaryActive State = iota
	StatePrimaryFailing
	StateSecondaryActive
	StateFailbackPending
)

func (s State) String() string {
	switch s {
	case StatePrimaryActive:
		return "PRIMARY_ACTIVE"
	case StatePrimaryFailing:
		return "PRIMARY_FAILING"
	case StateSecondaryActive:
		return "SECONDARY_ACTIVE"
	case StateFailbackPending:
		return "FAILBACK_PENDING"
	default:
		return "UNKNOWN"
	}
}

// Engine manages the failover state machine
type Engine struct {
	mu              sync.Mutex
	state           State
	failCount       int
	lastFailover    time.Time
	cooldown        time.Duration
	primaryCfg      *config.Config
	secondaryIP     string
	recovered       bool
}

// NewEngine creates a new failover engine
func NewEngine(cfg *config.Config) *Engine {
	return &Engine{
		state:       StatePrimaryActive,
		cooldown:    30 * time.Second, // Minimum time between failovers
		primaryCfg:  cfg,
		secondaryIP: cfg.Failover.SecondaryPublicIP,
	}
}

// Update processes a health report and updates failover state
func (e *Engine) Update(report health.Report) (action FailoverAction) {
	e.mu.Lock()
	defer e.mu.Unlock()

	switch e.state {
	case StatePrimaryActive:
		if !report.Healthy {
			e.failCount++
			if e.failCount >= e.primaryCfg.Failover.SwitchAfterFailures {
				e.state = StatePrimaryFailing
				action = FailoverActionSwitch
			}
		} else {
			e.failCount = 0
		}

	case StatePrimaryFailing:
		// Transition happens in SwitchToSecondary
		if e.canFailover() {
			e.state = StateSecondaryActive
			e.lastFailover = time.Now()
			action = FailoverActionSwitch
		}

	case StateSecondaryActive:
		if report.Healthy {
			e.recovered = true
			e.state = StateFailbackPending
			action = FailoverActionCheckPrimary
		}

	case StateFailbackPending:
		if report.Healthy {
			// Primary is back, fail over to it
			e.state = StatePrimaryActive
			e.failCount = 0
			e.recovered = false
			action = FailoverActionFailback
		} else {
			// Primary still down, stay on secondary
			e.state = StateSecondaryActive
		}
	}

	return action
}

// canFailover checks if enough time has passed since last failover
func (e *Engine) canFailover() bool {
	return time.Since(e.lastFailover) > e.cooldown
}

// GetState returns the current failover state
func (e *Engine) GetState() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.state
}

// GetFailCount returns current failure count
func (e *Engine) GetFailCount() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.failCount
}

// FailoverAction represents what the engine wants to do
type FailoverAction int

const (
	FailoverActionNone FailoverAction = iota
	FailoverActionSwitch
	FailoverActionFailback
	FailoverActionCheckPrimary
)

func (a FailoverAction) String() string {
	switch a {
	case FailoverActionNone:
		return "NONE"
	case FailoverActionSwitch:
		return "SWITCH"
	case FailoverActionFailback:
		return "FAILBACK"
	case FailoverActionCheckPrimary:
		return "CHECK_PRIMARY"
	default:
		return "UNKNOWN"
	}
}

// SwitchToSecondary rebuilds the tunnel with the secondary peer IP
func SwitchToSecondary(cfg *config.Config, secondaryIP string) error {
	cfg.Remote.PublicIP = secondaryIP
	return rebuildTunnel(cfg)
}

// FailbackToPrimary restores the primary peer IP
func FailbackToPrimary(cfg *config.Config, primaryIP string) error {
	cfg.Remote.PublicIP = primaryIP
	return rebuildTunnel(cfg)
}

// rebuildTunnel tears down and rebuilds the tunnel
func rebuildTunnel(cfg *config.Config) error {
	// Stop current tunnel
	_ = ipsec.Terminate(cfg)
	_ = gre.Down(cfg.TunnelName)
	routing.FlushStaticRoutes(cfg)

	// Rebuild GRE with new IP
	if err := gre.Create(cfg); err != nil {
		return fmt.Errorf("failover: rebuilding GRE: %w", err)
	}
	if err := gre.Up(cfg.TunnelName); err != nil {
		return fmt.Errorf("failover: bringing GRE up: %w", err)
	}

	// Rebuild IPsec
	if err := ipsec.WriteSwanctlConfig(cfg); err != nil {
		return fmt.Errorf("failover: writing swanctl config: %w", err)
	}
	if err := ipsec.Reload(cfg); err != nil {
		return fmt.Errorf("failover: reloading swanctl: %w", err)
	}
	if err := ipsec.LoadAndInitiate(cfg); err != nil {
		return fmt.Errorf("failover: initiating SA: %w", err)
	}

	// Re-apply routes
	if cfg.Routing.Enabled {
		if err := routing.ApplyStaticRoutes(cfg); err != nil {
			return fmt.Errorf("failover: applying routes: %w", err)
		}
	}

	return nil
}
