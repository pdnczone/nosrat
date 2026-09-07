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

type Report struct {
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

// pingGREPeer sends a small burst of ICMP echoes to the remote GRE address
// (i.e. through the tunnel, not the public IP) so a healthy result proves
// GRE + IPsec end-to-end, not just that the peer's WAN is up.
func pingGREPeer(target string, count int, timeoutSec int) (lossPct, avgMs float64, err error) {
	cmd := exec.Command("ping", "-c", strconv.Itoa(count), "-w", strconv.Itoa(timeoutSec), target)
	out, _ := cmd.CombinedOutput() // ping exits non-zero on packet loss; that's expected input, not a Go error
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
	r := Report{}

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
	return r
}

// Recover attempts to bring an unhealthy tunnel back without a reboot:
//  1. re-assert the GRE link (idempotent 'ip link set up')
//  2. ask strongSwan to re-initiate the IKE/ESP SA (DPD's restart action
//     usually already does this; this is the belt-and-braces path nosrat
//     drives itself so recovery does not depend solely on strongSwan timers)
func Recover(c *config.Config) error {
	if err := gre.Up(c.TunnelName); err != nil {
		return fmt.Errorf("recover: bringing GRE up: %w", err)
	}
	if err := ipsec.Terminate(c); err != nil {
		// non-fatal: SA may already be down
		_ = err
	}
	if err := ipsec.LoadAndInitiate(c); err != nil {
		return fmt.Errorf("recover: re-initiating IPsec SA: %w", err)
	}
	return nil
}

// RunLoop runs Check/Recover on the configured interval until stop is
// closed. Intended to be launched from the systemd service's main loop.
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
