package sidecar

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/client"
	"github.com/marcus/babysitter/go/pkg/plugin"
)

type BabysitterPlugin struct {
	info    plugin.PluginInfo
	client  *client.Client
	focused bool
}

func New() *BabysitterPlugin {
	return &BabysitterPlugin{
		info: plugin.PluginInfo{
			ID:          "babysitter",
			Name:        "Babysitter",
			Description: "Workflow orchestration for AI agents",
			Version:     "0.1.0",
		},
	}
}

func (p *BabysitterPlugin) Init(ctx *plugin.Context) error {
	baseURL := "http://localhost:4001"
	if url, ok := ctx.Config["daemon_url"].(string); ok {
		baseURL = url
	}
	p.client = client.New(baseURL)
	return nil
}

func (p *BabysitterPlugin) Update(msg tea.Msg) (plugin.Plugin, tea.Cmd) {
	return p, nil
}

func (p *BabysitterPlugin) View() string {
	return "Babysitter Plugin View"
}

func (p *BabysitterPlugin) Commands() []plugin.Command {
	return []plugin.Command{
		{ID: "refresh", Name: "Refresh", Handler: func() tea.Cmd { return nil }},
		{ID: "attach", Name: "Attach", Handler: func() tea.Cmd { return nil }},
	}
}

func (p *BabysitterPlugin) Info() plugin.PluginInfo {
	return p.info
}
