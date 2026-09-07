// nosrat is the lifecycle manager for a GRE-over-IPsec tunnel: it owns the
// kernel GRE interface, drives strongSwan for IKEv2/ESP, wires up routing
// and nftables, and runs health checks with automatic recovery.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/pdnczone/nosrat/internal/config"
	"github.com/pdnczone/nosrat/internal/diagnostics"
	"github.com/pdnczone/nosrat/internal/firewall"
	"github.com/pdnczone/nosrat/internal/gre"
	"github.com/pdnczone/nosrat/internal/health"
	"github.com/pdnczone/nosrat/internal/ipsec"
	"github.com/pdnczone/nosrat/internal/routing"
)

const (
	defaultConfigPath = "/etc/nosrat/tunnel.yaml"
	defaultPSKPath    = "/etc/nosrat/secrets/psk"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	cmd := os.Args[1]
	cfgPath := envOr("NOSRAT_CONFIG", defaultConfigPath)

	// `init` must work before a valid config exists, so handle it before
	// loading config.
	if cmd == "init" {
		if err := cmdInit(cfgPath); err != nil {
			fatal(err)
		}
		return
	}

	var cfg *config.Config
	var err error
	if cmd != "help" && cmd != "--help" && cmd != "-h" {
		cfg, err = config.Load(cfgPath)
		if err != nil {
			fatal(err)
		}
	}

	switch cmd {
	case "create":
		err = cmdCreate(cfg)
	case "start":
		err = cmdStart(cfg)
	case "stop":
		err = cmdStop(cfg)
	case "restart":
		if e := cmdStop(cfg); e != nil {
			fmt.Fprintln(os.Stderr, "warning during stop:", e)
		}
		time.Sleep(1 * time.Second)
		err = cmdStart(cfg)
	case "status":
		err = cmdStatus(cfg)
	case "health":
		err = cmdHealth(cfg)
	case "routes":
		err = cmdRoutes(cfg)
	case "ipsec":
		err = cmdIPsec(cfg)
	case "logs":
		err = cmdLogs()
	case "diagnose":
		err = cmdDiagnose(cfg)
	case "uninstall":
		err = cmdUninstall(cfg)
	case "run-daemon":
		err = cmdRunDaemon(cfg)
	default:
		usage()
		os.Exit(1)
	}

	if err != nil {
		fatal(err)
	}
}

func usage() {
	fmt.Println(`nosrat - GRE-over-IPsec tunnel manager (PDNC)

Usage: nosrat <command>

Commands:
  init        Create /etc/nosrat, generate a PSK, install a starter config
  create      (Re)build the GRE interface and strongSwan connection from config
  start       Bring the tunnel up (GRE + IPsec SA + routes + firewall)
  stop        Tear down IPsec SA and bring GRE down (config stays on disk)
  restart     stop, then start
  status      Human-readable tunnel/IPsec/traffic/health summary
  health      Run one health check pass and print the result
  routes      Show routes installed on the GRE interface
  ipsec       Show IKE/ESP SA detail
  logs        Tail nosrat + strongSwan systemd logs
  diagnose    Run the full diagnostic checklist
  uninstall   Remove GRE interface, strongSwan config, firewall rules`)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}

// ---- command implementations -------------------------------------------

func cmdInit(cfgPath string) error {
	if err := config.EnsureConfigDir(); err != nil {
		return err
	}

	if _, err := os.Stat(defaultPSKPath); os.IsNotExist(err) {
		psk, err := config.GeneratePSK()
		if err != nil {
			return fmt.Errorf("generating PSK: %w", err)
		}
		if err := os.WriteFile(defaultPSKPath, []byte(psk+"\n"), 0600); err != nil {
			return err
		}
		fmt.Println("generated new PSK at", defaultPSKPath, "(mode 0600)")
	} else {
		fmt.Println("PSK already exists at", defaultPSKPath, "- leaving it untouched")
	}

	if _, err := os.Stat(cfgPath); os.IsNotExist(err) {
		starterConfig := config.GetDefaultStarterConfig()
		if err := os.WriteFile(cfgPath, []byte(starterConfig), 0644); err != nil {
			return err
		}
		fmt.Println("wrote starter config to", cfgPath)
		fmt.Println("edit local/remote public_ip and gre_ip, then run: nosrat create && nosrat start")
	} else {
		fmt.Println("config already exists at", cfgPath, "- leaving it untouched")
	}
	return nil
}

func cmdCreate(c *config.Config) error {
	fmt.Println("[1/4] creating GRE interface", c.TunnelName)
	if err := gre.Create(c); err != nil {
		return err
	}
	fmt.Println("[2/4] writing strongSwan swanctl config")
	if err := ipsec.WriteSwanctlConfig(c); err != nil {
		return err
	}
	fmt.Println("[3/4] applying kernel routing/sysctl settings")
	if err := routing.Enable(c); err != nil {
		return err
	}
	fmt.Println("[4/4] done. Run 'nosrat start' to bring the tunnel up.")
	return nil
}

func cmdStart(c *config.Config) error {
	if !gre.Exists(c.TunnelName) {
		if err := cmdCreate(c); err != nil {
			return err
		}
	}
	if err := gre.Up(c.TunnelName); err != nil {
		return err
	}
	if err := ipsec.EnsureRunning(); err != nil {
		return err
	}
	if err := ipsec.Reload(c); err != nil {
		return err
	}
	if err := ipsec.LoadAndInitiate(c); err != nil {
		return err
	}
	if c.Routing.Enabled {
		if err := routing.ApplyStaticRoutes(c); err != nil {
			return err
		}
	}
	if err := firewall.Apply(c); err != nil {
		return err
	}
	fmt.Println("tunnel", c.TunnelName, "started")
	return nil
}

func cmdStop(c *config.Config) error {
	if err := ipsec.Terminate(c); err != nil {
		fmt.Fprintln(os.Stderr, "warning:", err)
	}
	if err := gre.Down(c.TunnelName); err != nil {
		return err
	}
	routing.FlushStaticRoutes(c)
	fmt.Println("tunnel", c.TunnelName, "stopped")
	return nil
}

func cmdStatus(c *config.Config) error {
	link, _ := gre.Status(c.TunnelName)
	sa := ipsec.Status(c)
	h := health.Check(c)

	fmt.Println("GRE Tunnel")
	fmt.Println(strings.Repeat("-", 28))
	fmt.Println("Name:      ", c.TunnelName)
	fmt.Println("Status:    ", stateOf(link.Exists, link.OperState))
	fmt.Println("Local:     ", c.LocalGREAddr())
	fmt.Println("Remote:    ", c.RemoteGREAddr())
	fmt.Println("MTU:       ", link.MTU)
	fmt.Println()
	fmt.Println("IPsec")
	fmt.Println(strings.Repeat("-", 28))
	fmt.Println("IKE:       ", sa.IKEState)
	fmt.Println("ESP:       ", sa.ESPState)
	fmt.Println("Encryption:", orDash(sa.Encryption))
	fmt.Println("PFS:       ", orDash(sa.PFSGroup))
	fmt.Println()
	fmt.Println("Health")
	fmt.Println(strings.Repeat("-", 28))
	fmt.Printf("Latency:    %.0f ms\n", h.LatencyMs)
	fmt.Printf("Packet Loss: %.0f%%\n", h.PacketLoss)
	if !h.Healthy {
		fmt.Println("Unhealthy reasons:")
		for _, reason := range h.Reasons {
			fmt.Println("  -", reason)
		}
	}
	return nil
}

func stateOf(exists bool, operState string) string {
	if !exists {
		return "MISSING"
	}
	return operState
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func cmdHealth(c *config.Config) error {
	r := health.Check(c)
	fmt.Printf("healthy=%v gre_up=%v ike=%s esp=%s latency=%.1fms loss=%.1f%%\n",
		r.Healthy, r.GREUp, r.IKEState, r.ESPState, r.LatencyMs, r.PacketLoss)
	for _, reason := range r.Reasons {
		fmt.Println("  -", reason)
	}
	if !r.Healthy && !c.Health.AutoRecover {
		fmt.Println("(auto_recover is disabled in config; run 'nosrat restart' manually)")
	}
	return nil
}

func cmdRoutes(c *config.Config) error {
	out, err := routing.List(c)
	if err != nil {
		return err
	}
	fmt.Print(out)
	return nil
}

func cmdIPsec(c *config.Config) error {
	out, err := exec.Command("swanctl", "--list-sas").CombinedOutput()
	fmt.Print(string(out))
	return err
}

func cmdLogs() error {
	cmd := exec.Command("journalctl", "-u", "nosrat", "-u", "strongswan", "-n", "200", "--no-pager")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func cmdDiagnose(c *config.Config) error {
	results := diagnostics.RunAll(c)
	diagnostics.Print(results)
	return nil
}

func cmdUninstall(c *config.Config) error {
	fmt.Println("stopping tunnel...")
	_ = cmdStop(c)
	fmt.Println("removing firewall rules...")
	_ = firewall.Remove()
	fmt.Println("removing GRE interface...")
	_ = gre.Delete(c.TunnelName)
	fmt.Println("removing swanctl config for", c.TunnelName)
	_ = os.Remove("/etc/swanctl/conf.d/" + c.TunnelName + ".conf")
	_ = ipsec.Reload(c)
	fmt.Println("removing sysctl config...")
	_ = routing.RemoveSysctlConfig()
	fmt.Println("done. Config and PSK under /etc/nosrat were left in place;")
	fmt.Println("remove /etc/nosrat manually if you want a fully clean slate.")
	return nil
}

func cmdRunDaemon(c *config.Config) error {
	stop := make(chan struct{})
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)

	go health.RunLoop(c, stop, func(r health.Report) {
		if !r.Healthy {
			fmt.Fprintln(os.Stderr, "health check failed:", r.Reasons)
		}
	})

	<-sig
	close(stop)
	fmt.Println("nosrat daemon shutting down")
	return nil
}
