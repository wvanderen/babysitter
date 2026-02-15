package tui

import (
	"fmt"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/marcus/babysitter/go/internal/client"
)

type FocusArea int

const (
	FocusSessions FocusArea = iota
	FocusOutput
	FocusControls
)

var (
	appStyle = lipgloss.NewStyle().Padding(1, 2)
)

type AppModel struct {
	sessionsList SessionList
	outputViewer OutputViewer
	controls     Controls
	focus        FocusArea
	client       *client.Client
	wsClient     *client.WSClient
	sessions     []client.Session
	currentIndex int
	connected    bool
	quitting     bool
	err          error
}

func NewAppModel(apiClient *client.Client) AppModel {
	return AppModel{
		sessionsList: NewSessionList(),
		outputViewer: NewOutputViewer(),
		controls:     NewControls(),
		focus:        FocusSessions,
		client:       apiClient,
		sessions:     []client.Session{},
		currentIndex: 0,
		connected:    false,
		quitting:     false,
	}
}

func (m AppModel) Init() tea.Cmd {
	return tea.Batch(
		m.sessionsList.Init(),
		m.outputViewer.Init(),
		m.controls.Init(),
		m.fetchSessions(),
	)
}

func (m AppModel) fetchSessions() tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return SessionListMsg{Sessions: []SessionItem{}}
		}
		result, err := m.client.ListSessions()
		if err != nil {
			return errMsg{err}
		}
		items := make([]SessionItem, len(result.Sessions))
		for i, s := range result.Sessions {
			items[i] = SessionItem{
				ID:      s.ID,
				IssueID: s.IssueID,
				Stage:   s.CurrentStage,
				Status:  s.Status,
			}
		}
		return SessionListMsg{Sessions: items}
	}
}

type errMsg struct{ error }

type FocusMsg struct {
	Area FocusArea
}

func (e errMsg) Error() string { return e.error.Error() }

func (m AppModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			return m, tea.Quit
		case "tab":
			m.cycleFocus()
		case "shift+tab":
			m.cycleFocusBack()
		}

	case tea.WindowSizeMsg:
		h, v := appStyle.GetFrameSize()
		m.sessionsList.SetSize(msg.Width/2-h, msg.Height-v-10)
		m.outputViewer.SetSize(msg.Width/2-h, msg.Height-v-10)

	case SessionListMsg:
		sessions := make([]list.Item, len(msg.Sessions))
		for i, s := range msg.Sessions {
			sessions[i] = s
		}
		m.sessionsList.list.SetItems(sessions)

	case errMsg:
		m.err = msg

	case client.WSMessage:
		m.handleWSMessage(msg)

	case FocusMsg:
		m.focus = msg.Area
		m.sessionsList.SetFocused(m.focus == FocusSessions)
		m.outputViewer.SetFocused(m.focus == FocusOutput)
		m.controls.SetFocused(m.focus == FocusControls)
	}

	var cmd tea.Cmd
	m.sessionsList, cmd = m.sessionsList.Update(msg)
	cmds = append(cmds, cmd)

	m.outputViewer, cmd = m.outputViewer.Update(msg)
	cmds = append(cmds, cmd)

	m.controls, cmd = m.controls.Update(msg)
	cmds = append(cmds, cmd)

	if selected := m.sessionsList.SelectedSession(); selected != nil {
		m.controls.SetSession(selected)
	}

	return m, tea.Batch(cmds...)
}

func (m *AppModel) cycleFocus() {
	m.sessionsList.SetFocused(m.focus == FocusSessions)
	m.outputViewer.SetFocused(m.focus == FocusOutput)
	m.controls.SetFocused(m.focus == FocusControls)

	switch m.focus {
	case FocusSessions:
		m.focus = FocusOutput
	case FocusOutput:
		m.focus = FocusControls
	case FocusControls:
		m.focus = FocusSessions
	}

	m.sessionsList.SetFocused(m.focus == FocusSessions)
	m.outputViewer.SetFocused(m.focus == FocusOutput)
	m.controls.SetFocused(m.focus == FocusControls)
}

func (m *AppModel) cycleFocusBack() {
	switch m.focus {
	case FocusSessions:
		m.focus = FocusControls
	case FocusOutput:
		m.focus = FocusSessions
	case FocusControls:
		m.focus = FocusOutput
	}
}

func (m AppModel) handleWSMessage(msg client.WSMessage) {
	switch msg.Event {
	case "output":
		m.outputViewer.AppendOutput(msg.Output)
	case "session_started", "session_updated", "session_completed":
		_ = m.fetchSessions()
	}
}

func (m AppModel) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}

	var errView string
	if m.err != nil {
		errView = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render(
			fmt.Sprintf("Error: %v", m.err))
	}

	leftPanel := m.sessionsList.View()
	rightPanel := m.outputViewer.View()
	controlsPanel := m.controls.View()

	panels := lipgloss.JoinHorizontal(lipgloss.Top, leftPanel, rightPanel)

	var focusIndicator string
	switch m.focus {
	case FocusSessions:
		focusIndicator = "[Sessions] Output  Controls"
	case FocusOutput:
		focusIndicator = "Sessions [Output]  Controls"
	case FocusControls:
		focusIndicator = "Sessions  Output  [Controls]"
	}

	header := lipgloss.NewStyle().Bold(true).Render("BABYSITTER TUI") + "  " +
		helpStyle.Render("[Tab] Switch focus  [q] Quit")

	focusBar := helpStyle.Render(focusIndicator)

	return appStyle.Render(
		lipgloss.JoinVertical(lipgloss.Left,
			header,
			"",
			panels,
			"",
			focusBar,
			controlsPanel,
			errView,
		),
	)
}

func (m *AppModel) SetSessions(sessions []client.Session) {
	m.sessions = sessions
}
