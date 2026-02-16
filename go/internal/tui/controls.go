package tui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
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
	ActionEscalate
	ActionSkip
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
		buttons:  []string{"Pause", "Resume", "Escalate", "Skip", "Attach", "Refresh"},
		helpText: "[p] Pause  [r] Resume  [e] Escalate  [k] Skip  [a] Attach  [R] Refresh",
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
			case "left":
				c.PrevButton()
			case "right":
				c.NextButton()
			case "enter":
				return c, c.executeSelectedButton()
			case "p":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionPause, SessionID: c.session.ID}
				}
			case "r":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionResume, SessionID: c.session.ID}
				}
			case "e":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionEscalate, SessionID: c.session.ID}
				}
			case "k":
				return c, func() tea.Msg {
					return ControlMsg{Action: ActionSkip, SessionID: c.session.ID}
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

func (c Controls) executeSelectedButton() tea.Cmd {
	var action ControlAction
	switch c.selected {
	case 0:
		action = ActionPause
	case 1:
		action = ActionResume
	case 2:
		action = ActionEscalate
	case 3:
		action = ActionSkip
	case 4:
		action = ActionAttach
	case 5:
		action = ActionRefresh
	}
	return func() tea.Msg {
		return ControlMsg{Action: action, SessionID: c.session.ID}
	}
}

func (c Controls) View() string {
	ctrlStyle := styles.PanelInactive
	if c.focused {
		ctrlStyle = styles.PanelActive
	}

	var buttons []string
	for i, btn := range c.buttons {
		btnStyle := styles.ResolveButtonStyle(i == c.selected && c.focused, false, false)
		buttons = append(buttons, btnStyle.Render(btn))
	}

	buttonRow := lipgloss.JoinHorizontal(lipgloss.Top, buttons...)
	help := styles.KeyHint.Render(c.helpText)

	var statusLine string
	if c.session != nil {
		statusLine = fmt.Sprintf("Session: %s | Status: %s",
			c.session.ID,
			FormatStatus(c.session.Status))
	} else {
		statusLine = styles.Muted.Render("No session selected")
	}

	return ctrlStyle.Render(
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
