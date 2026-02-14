package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/client"
	"github.com/marcus/babysitter/go/internal/tui"
)

var (
	defaultAPIURL = "http://localhost:4001"
)

func main() {
	apiURL := flag.String("api", defaultAPIURL, "Daemon API URL")
	flag.Parse()

	apiClient := client.New(*apiURL)

	model := tui.NewAppModel(apiClient)

	p := tea.NewProgram(model,
		tea.WithAltScreen(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
