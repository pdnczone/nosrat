// Package health runs periodic checks against the tunnel and can trigger
// recovery actions (restart IPsec SA, re-apply GRE) without requiring a
// full reboot.
package health

import (
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"time"

	"github.com/pdnczone/nosrat/internal/config"
	"github.com/pdnczone/nosrat/internal/gre"
	"github.com/pdnczone/nosrat/internal/ipsec"
)

// TunnelState represents the overall health state of the tunnel.
type TunnelState int

const (
	StateDown TunnelState = iota
	StateStarting
	StateDegraded
	StateUp
	StateFailing
	StateRecovering
)

func (s TunnelState) String() string {
	switch s {
	case StateDown:
		return "DOWN"
	case StateStarting:
		return "STARTING"
	case StateDegraded:
		return "DEGRADED"
	case StateUp:
		return "UP"
	case StateFailing:
		return "FAILING"
	case StateRecovering:
		return "RECOVERING"
	default:
		return "UNKNOWN"
	}
}

type Report struct {
	State      TunnelState
	GREUp      bool
	IKEState   string
	ESPState   string
	LatencyMs  float64
	PacketLoss float64
	Healthy    bool
	Reasons    []string
}

var (
	lossRe   = regexp.MustCompile(`(\d+(?:\.\d+)?)% packet loss`)
	rttAvgRe = regexp.MustCompile(`= [\d.]+/([\d.]+)/`)
)

// pingGREPeer sends a small burst of ICMP echoes to the remote GRE address.
func pingGREPeer(target string, count int, timeoutSec int) (lossPct, avgMs float64, err error) {
	cmd := exec.Command("ping", "-c", strconv.Itoa(count), "-w", strconv.Itoa(timeoutSec), target)
	out, _ := cmd.CombinedOutput()
	text := string(out)

	if m := lossRe.FindStringSubmatch(text); m != nil {
		lossPct, _ = strconv.ParseFloat(m[1], 64)
	} else {
		return 100, 0, fmt.Errorf("could not parse ping output: %s", text)
	}
	if m := rttAvgRe.FindStringSubmatch(text); m != nil {
		avgMs, _ = strconv.ParseFloat(m[1], 64)
	}
	return lossPct, avgMs, nil
}

// Check runs one full health pass.
func Check(c *config.Config) Report {
	r := Report{State: StateDown}

	st, _ := gre.Status(c.TunnelName)
	r.GREUp = st.Exists && st.OperState == "UP"
	if !r.GREUp {
		r.Reasons = append(r.Reasons, fmt.Sprintf("GRE interface %s is not UP (state=%s, exists=%v)", c.TunnelName, st.OperState, st.Exists))
	}

	sa := ipsec.Status(c)
	r.IKEState = sa.IKEState
	r.ESPState = sa.ESPState
	if sa.IKEState != "ESTABLISHED" {
		r.Reasons = append(r.Reasons, "IKE SA is not ESTABLISHED (state="+sa.IKEState+")")
	}
	if sa.ESPState != "INSTALLED" {
		r.Reasons = append(r.Reasons, "ESP SA is not INSTALLED (state="+sa.ESPState+")")
	}

	if r.GREUp {
		loss, avg, err := pingGREPeer(c.RemoteGREAddr(), 5, 5)
		if err != nil {
			r.Reasons = append(r.Reasons, "ping over GRE failed: "+err.Error())
			r.PacketLoss = 100
		} else {
			r.PacketLoss = loss
			r.LatencyMs = avg
			if loss > c.Health.LossThresholdPct {
				r.Reasons = append(r.Reasons, fmt.Sprintf("packet loss %.1f%% exceeds threshold %.1f%%", loss, c.Health.LossThresholdPct))
			}
			if avg > float64(c.Health.LatencyThresholdMs) && avg > 0 {
				r.Reasons = append(r.Reasons, fmt.Sprintf("latency %.1fms exceeds threshold %dms", avg, c.Health.LatencyThresholdMs))
			}
		}
	}

	r.Healthy = len(r.Reasons) == 0

	// Determine state
	switch {
	case r.Healthy:
		r.State = StateUp
	case !r.GREUp:
		r.State = StateDown
	case sa.IKEState != "ESTABLISHED" || sa.ESPState != "INSTALLED":
		r.State = StateDegraded
	default:
		r.State = StateDegraded
	}

	return r
}

// Recover attempts to bring an unhealthy tunnel back without a reboot.
func Recover(c *config.Config) error {
	if err := gre.Up(c.TunnelName); err != nil {
		return fmt.Errorf("recover: bringing GRE up: %w", err)
	}
	if err := ipsec.Terminate(c); err != nil {
		// non-fatal: SA may already be down
	}
	if err := ipsec.LoadAndInitiate(c); err != nil {
		return fmt.Errorf("recover: re-initiating IPsec SA: %w", err)
	}
	return nil
}

// RunLoop runs Check/Recover on the configured interval until stop is closed.
func RunLoop(c *config.Config, stop <-chan struct{}, onReport func(Report)) {
	ticker := time.NewTicker(time.Duration(c.Health.IntervalSeconds) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			r := Check(c)
			if onReport != nil {
				onReport(r)
			}
			if !r.Healthy && c.Health.AutoRecover {
				_ = Recover(c)
			}
		}
	}
}
