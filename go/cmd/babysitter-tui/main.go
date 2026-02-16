package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/sidecar"
	"github.com/wvanderen/babysitter/go/pkg/plugin"
)

var (
	defaultAPIURL = "http://localhost:4000"
	version       = "dev"
)

func main() {
	var (
		apiURL      = flag.String("api", defaultAPIURL, "Daemon API URL")
		wsURL       = flag.String("ws", "", "WebSocket URL (defaults to ws://<api-host>/ws)")
		sessionID   = flag.String("session", "", "Session ID to select on start")
		noConnect   = flag.Bool("no-connect", false, "Disable auto WebSocket connection")
		showVer     = flag.Bool("version", false, "Show version and exit")
		noAltScreen = flag.Bool("no-alt-screen", false, "Disable alternate screen buffer")
	)
	flag.Parse()

	if *showVer {
		fmt.Printf("babysitter-tui %s\n", version)
		os.Exit(0)
	}

	config := map[string]interface{}{
		"daemon_url": *apiURL,
	}
	if *wsURL != "" {
		config["ws_url"] = *wsURL
	}
	if *sessionID != "" {
		config["session_id"] = *sessionID
	}
	if !*noConnect {
		config["auto_connect"] = true
	}

	bp := sidecar.New()
	ctx := &plugin.Context{Config: config}

	if err := bp.Init(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Init error: %v\n", err)
		os.Exit(1)
	}

	opts := []tea.ProgramOption{tea.WithAltScreen()}
	if *noAltScreen {
		opts = []tea.ProgramOption{}
	}

	p := tea.NewProgram(pluginAdapter{bp}, opts...)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

type pluginAdapter struct {
	*sidecar.BabysitterPlugin
}

func (a pluginAdapter) Init() tea.Cmd {
	return a.BabysitterPlugin.AppModel().Init()
}

func (a pluginAdapter) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	updated, cmd := a.BabysitterPlugin.Update(msg)
	return pluginAdapter{updated.(*sidecar.BabysitterPlugin)}, cmd
}

func (a pluginAdapter) View() string {
	return a.BabysitterPlugin.View()
}
