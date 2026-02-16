package sidecar

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/tui"
	"github.com/wvanderen/babysitter/go/pkg/plugin"
)

type WSConnectMsg struct {
	Connected bool
}

type JoinSessionMsg struct {
	SessionID string
}

type BabysitterPlugin struct {
	info          plugin.PluginInfo
	client        *client.Client
	wsClient      *client.WSClient
	appModel      tui.AppModel
	commands      []plugin.Command
	quitting      bool
	wsMessages    chan client.WSMessage
	currentSessID string
}

func New() *BabysitterPlugin {
	return &BabysitterPlugin{
		info: plugin.PluginInfo{
			ID:          "babysitter",
			Name:        "Babysitter",
			Description: "Workflow orchestration for AI agents",
			Version:     "0.1.0",
		},
		wsMessages: make(chan client.WSMessage, 100),
	}
}

func (p *BabysitterPlugin) Init(ctx *plugin.Context) error {
	baseURL := "http://localhost:4000"
	if url, ok := ctx.Config["daemon_url"].(string); ok && url != "" {
		baseURL = url
	}
	p.client = client.New(baseURL)
	p.appModel = tui.NewAppModel(p.client)
	p.initCommands()

	if autoConnect, ok := ctx.Config["auto_connect"].(bool); ok && autoConnect {
		p.connectWebSocket()
	}

	return nil
}

func (p *BabysitterPlugin) connectWebSocket() {
	ws, err := p.client.WebSocket()
	if err != nil {
		return
	}
	p.wsClient = ws

	go func() {
		for {
			msg, err := ws.ReadMessage()
			if err != nil {
				return
			}
			select {
			case p.wsMessages <- msg:
			default:
			}
		}
	}()
}

func (p *BabysitterPlugin) pollWSMessages() tea.Cmd {
	return func() tea.Msg {
		return <-p.wsMessages
	}
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
	var cmds []tea.Cmd

	if p.wsClient != nil {
		cmds = append(cmds, p.pollWSMessages())
	}

	switch m := msg.(type) {
	case JoinSessionMsg:
		if p.wsClient != nil {
			if p.currentSessID != "" {
				p.wsClient.LeaveSession(p.currentSessID)
			}
			if m.SessionID != "" {
				p.wsClient.JoinSession(m.SessionID)
				p.currentSessID = m.SessionID
			}
		}
	case tui.InstanceLoadedMsg:
		if m.Instance != nil && m.Instance.SessionID != "" && m.Instance.SessionID != p.currentSessID {
			cmds = append(cmds, func() tea.Msg {
				return JoinSessionMsg{SessionID: m.Instance.SessionID}
			})
		}
	}

	updated, cmd := p.appModel.Update(msg)
	cmds = append(cmds, cmd)
	switch v := updated.(type) {
	case tui.AppModel:
		p.appModel = v
	case *tui.AppModel:
		p.appModel = *v
	}

	if keyMsg, ok := msg.(tea.KeyMsg); ok {
		if keyMsg.String() == "q" || keyMsg.String() == "ctrl+c" {
			p.quitting = true
		}
	}

	return p, tea.Batch(cmds...)
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
