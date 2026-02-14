package tui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	controlStyle = lipgloss.NewStyle().
			Padding(1, 2).
			Border(lipgloss.NormalBorder(), false, false, true, false).
			BorderForeground(lipgloss.Color("62"))

	buttonStyle = lipgloss.NewStyle().
			Padding(0, 2).
			Foreground(lipgloss.Color("170"))

	buttonActiveStyle = lipgloss.NewStyle().
				Padding(0, 2).
				Background(lipgloss.Color("62")).
				Foreground(lipgloss.Color("230"))

	helpKeyStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("86"))
)

type ControlAction int

const (
	ActionNone ControlAction = iota
	ActionStart
	ActionStop
	ActionPause
	ActionResume
	ActionAttach
	ActionRefresh
)

type ControlMsg struct {
	Action    ControlAction
	SessionID string
}

type Controls struct {
	focused   bool
	selected  int
	buttons   []string
	helpText  string
	sessionID string
	session   *SessionItem
}

func NewControls() Controls {
	return Controls{
		focused:  true,
		selected: 0,
		buttons:  []string{"Start", "Stop", "Pause", "Resume", "Attach", "Refresh"},
		helpText: "[s] Start  [x] Stop  [p] Pause  [r] Resume  [a] Attach  [R] Refresh",
	}
}

func (c Controls) Init() tea.Cmd {
	return nil
}

func (c Controls) Update(msg tea.Msg) (Controls, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if c.focused && c.session != nil {
			switch msg.String() {
			case "s":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionStart, SessionID: c.session.ID}
				}
			case "x":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionStop, SessionID: c.session.ID}
				}
			case "p":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionPause, SessionID: c.session.ID}
				}
			case "r":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionResume, SessionID: c.session.ID}
				}
			case "a":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionAttach, SessionID: c.session.ID}
				}
			case "R":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionRefresh, SessionID: c.session.ID}
				}
			}
		}
	case ControlMsg:
		cmd = func() tea.Msg { return msg }
	}

	return c, cmd
}

func (c Controls) View() string {
	var buttons []string
	for i, btn := range c.buttons {
		if i == c.selected && c.focused {
			buttons = append(buttons, buttonActiveStyle.Render(btn))
		} else {
			buttons = append(buttons, buttonStyle.Render(btn))
		}
	}

	buttonRow := lipgloss.JoinHorizontal(lipgloss.Top, buttons...)
	help := helpStyle.Render(c.helpText)

	var statusLine string
	if c.session != nil {
		statusLine = fmt.Sprintf("Session: %s | Status: %s",
			c.session.ID,
			FormatStatus(c.session.Status))
	} else {
		statusLine = helpStyle.Render("No session selected")
	}

	return controlStyle.Render(
		lipgloss.JoinVertical(lipgloss.Left,
			buttonRow,
			"",
			statusLine,
			help,
		),
	)
}

func (c *Controls) SetFocused(focused bool) {
	c.focused = focused
}

func (c *Controls) SetSession(session *SessionItem) {
	c.session = session
}

func (c *Controls) NextButton() {
	c.selected = (c.selected + 1) % len(c.buttons)
}

func (c *Controls) PrevButton() {
	c.selected--
	if c.selected < 0 {
		c.selected = len(c.buttons) - 1
	}
}
