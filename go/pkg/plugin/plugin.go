package plugin

import (
	tea "github.com/charmbracelet/bubbletea"
)

type Plugin interface {
	Init(ctx *Context) error
	Update(msg tea.Msg) (Plugin, tea.Cmd)
	View() string
	Commands() []Command
}

type Context struct {
	Config map[string]interface{}
}

type Command struct {
	ID      string
	Name    string
	Handler func() tea.Cmd
}

type PluginInfo struct {
	ID          string
	Name        string
	Description string
	Version     string
}

func Register(info PluginInfo, factory func() Plugin) {
}
