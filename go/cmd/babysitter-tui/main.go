package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/sidecar"
	"github.com/marcus/babysitter/go/pkg/plugin"
)

var (
	defaultAPIURL = "http://localhost:4001"
)

func main() {
	apiURL := flag.String("api", defaultAPIURL, "Daemon API URL")
	flag.Parse()

	bp := sidecar.New()
	ctx := &plugin.Context{
		Config: map[string]interface{}{
			"daemon_url": *apiURL,
		},
	}

	if err := bp.Init(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Init error: %v\n", err)
		os.Exit(1)
	}

	p := tea.NewProgram(pluginAdapter{bp},
		tea.WithAltScreen(),
	)

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
