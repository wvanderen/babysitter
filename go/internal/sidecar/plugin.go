package sidecar

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/client"
	"github.com/marcus/babysitter/go/internal/tui"
	"github.com/marcus/babysitter/go/pkg/plugin"
)

type BabysitterPlugin struct {
	info     plugin.PluginInfo
	client   *client.Client
	appModel tui.AppModel
	commands []plugin.Command
	quitting bool
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
	if url, ok := ctx.Config["daemon_url"].(string); ok && url != "" {
		baseURL = url
	}
	p.client = client.New(baseURL)
	p.appModel = tui.NewAppModel(p.client)
	p.initCommands()
	return nil
}

func (p *BabysitterPlugin) initCommands() {
	p.commands = []plugin.Command{
		{
			ID:   "babysitter.pause",
			Name: "Pause Session",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionPause)
			},
		},
		{
			ID:   "babysitter.resume",
			Name: "Resume Session",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionResume)
			},
		},
		{
			ID:   "babysitter.escalate",
			Name: "Escalate Session",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionEscalate)
			},
		},
		{
			ID:   "babysitter.skip",
			Name: "Skip Stage",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionSkip)
			},
		},
		{
			ID:   "babysitter.attach",
			Name: "Attach to Session",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionAttach)
			},
		},
		{
			ID:   "babysitter.refresh",
			Name: "Refresh Sessions",
			Handler: func() tea.Cmd {
				return p.sendControlMsg(tui.ActionRefresh)
			},
		},
		{
			ID:   "babysitter.focus.sessions",
			Name: "Focus Sessions Panel",
			Handler: func() tea.Cmd {
				return p.setFocus(tui.FocusSessions)
			},
		},
		{
			ID:   "babysitter.focus.output",
			Name: "Focus Output Panel",
			Handler: func() tea.Cmd {
				return p.setFocus(tui.FocusOutput)
			},
		},
		{
			ID:   "babysitter.focus.controls",
			Name: "Focus Controls Panel",
			Handler: func() tea.Cmd {
				return p.setFocus(tui.FocusControls)
			},
		},
	}
}

func (p *BabysitterPlugin) sendControlMsg(action tui.ControlAction) tea.Cmd {
	return func() tea.Msg {
		return tui.ControlMsg{Action: action}
	}
}

func (p *BabysitterPlugin) setFocus(area tui.FocusArea) tea.Cmd {
	return func() tea.Msg {
		return tui.FocusMsg{Area: area}
	}
}

func (p *BabysitterPlugin) Update(msg tea.Msg) (plugin.Plugin, tea.Cmd) {
	updated, cmd := p.appModel.Update(msg)
	p.appModel = updated.(tui.AppModel)

	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		if keyMsg.String() == "q" || keyMsg.String() == "ctrl+c" {
			p.quitting = true
		}
	}

	return p, cmd
}

func (p *BabysitterPlugin) View() string {
	return p.appModel.View()
}

func (p *BabysitterPlugin) Commands() []plugin.Command {
	return p.commands
}

func (p *BabysitterPlugin) Info() plugin.PluginInfo {
	return p.info
}

func (p *BabysitterPlugin) AppModel() *tui.AppModel {
	return &p.appModel
}

func (p *BabysitterPlugin) IsQuitting() bool {
	return p.quitting
}
