package tui

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
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

type ViewState int

const (
	ViewNormal ViewState = iota
	ViewWorkflowSelect
	ViewNewSession
)

var (
	appStyle = lipgloss.NewStyle().Padding(1, 2)
)

type AppModel struct {
	sessionsList   SessionList
	outputViewer   OutputViewer
	controls       Controls
	workflowSelect WorkflowSelect
	newSession     *NewSession
	focus          FocusArea
	viewState      ViewState
	client         *client.Client
	wsClient       *client.WSClient
	sessions       []client.Session
	currentIndex   int
	connected      bool
	quitting       bool
	err            error
}

func NewAppModel(apiClient *client.Client) AppModel {
	return AppModel{
		sessionsList:   NewSessionList(),
		outputViewer:   NewOutputViewer(),
		controls:       NewControls(),
		workflowSelect: NewWorkflowSelect(),
		focus:          FocusSessions,
		viewState:      ViewNormal,
		client:         apiClient,
		sessions:       []client.Session{},
		currentIndex:   0,
		connected:      false,
		quitting:       false,
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

func (m AppModel) fetchWorkflows() tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return WorkflowSelectMsg{Workflows: []client.Workflow{}}
		}
		result, err := m.client.ListWorkflows()
		if err != nil {
			return errMsg{err}
		}
		return WorkflowSelectMsg{Workflows: result.Workflows}
	}
}

type errMsg struct{ error }

type FocusMsg struct {
	Area FocusArea
}

type ExecuteWorkflowMsg struct {
	WorkflowID string
	IssueID    string
	Variables  map[string]interface{}
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
		case "n":
			if m.viewState == ViewNormal {
				m.viewState = ViewWorkflowSelect
				return m, m.fetchWorkflows()
			}
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

	case ControlMsg:
		cmds = append(cmds, m.handleControlAction(msg))

	case WorkflowSelectedMsg:
		m.viewState = ViewNewSession
		m.newSession = &NewSession{
			workflowID:   msg.Workflow.ID,
			workflowName: msg.Workflow.Name,
			issueID:      textinput.New(),
		}
		m.newSession.issueID.Placeholder = "td-123"
		m.newSession.issueID.Focus()
		m.newSession.issueID.Prompt = "Issue ID: "

	case CancelWorkflowSelectMsg:
		m.viewState = ViewNormal

	case ExecuteWorkflowMsg:
		return m.handleExecuteWorkflow(msg)

	case NewSessionStartedMsg:
		m.viewState = ViewNormal
		m.newSession = nil
		m.outputViewer.AppendOutput(fmt.Sprintf("Workflow started! Session: %s Instance: %s\n", msg.SessionID, msg.InstanceID))
		cmds = append(cmds, m.fetchSessions())

	case NewSessionCanceledMsg:
		m.viewState = ViewNormal
		m.newSession = nil
	}

	var cmd tea.Cmd
	m.sessionsList, cmd = m.sessionsList.Update(msg)
	cmds = append(cmds, cmd)

	m.outputViewer, cmd = m.outputViewer.Update(msg)
	cmds = append(cmds, cmd)

	m.controls, cmd = m.controls.Update(msg)
	cmds = append(cmds, cmd)

	if m.viewState == ViewWorkflowSelect {
		m.workflowSelect, cmd = m.workflowSelect.Update(msg)
		cmds = append(cmds, cmd)
	}

	if m.viewState == ViewNewSession && m.newSession != nil {
		updatedNewSession, cmd := m.newSession.Update(msg)
		m.newSession = &updatedNewSession
		cmds = append(cmds, cmd)
	}

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

	switch m.viewState {
	case ViewWorkflowSelect:
		header := lipgloss.NewStyle().Bold(true).Render("BABYSITTER TUI") + "  " +
			helpStyle.Render("[Enter] Select  [Esc] Cancel  [q] Quit")
		return appStyle.Render(
			lipgloss.JoinVertical(lipgloss.Left,
				header,
				"",
				m.workflowSelect.View(),
			),
		)

	case ViewNewSession:
		header := lipgloss.NewStyle().Bold(true).Render("BABYSITTER TUI") + "  " +
			helpStyle.Render("[Enter] Start  [Esc] Cancel  [q] Quit")
		return appStyle.Render(
			lipgloss.JoinVertical(lipgloss.Left,
				header,
				"",
				m.newSession.View(),
			),
		)
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
		helpStyle.Render("[Tab] Switch focus  [n] New session  [q] Quit")

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

type ActionResult struct {
	Action  string
	Success bool
	Message string
}

func (m *AppModel) handleControlAction(msg ControlMsg) tea.Cmd {
	if m.client == nil {
		return func() tea.Msg {
			return ActionResult{Action: "control", Success: false, Message: "no client"}
		}
	}

	switch msg.Action {
	case ActionPause:
		return func() tea.Msg {
			err := m.client.PauseSession(msg.SessionID)
			if err != nil {
				return ActionResult{Action: "pause", Success: false, Message: err.Error()}
			}
			return ActionResult{Action: "pause", Success: true, Message: "Session paused"}
		}

	case ActionResume:
		return func() tea.Msg {
			err := m.client.ResumeSession(msg.SessionID)
			if err != nil {
				return ActionResult{Action: "resume", Success: false, Message: err.Error()}
			}
			return ActionResult{Action: "resume", Success: true, Message: "Session resumed"}
		}

	case ActionEscalate:
		return func() tea.Msg {
			err := m.client.InterveneSession(msg.SessionID, client.InterventionEscalate, "manual escalation via TUI")
			if err != nil {
				return ActionResult{Action: "escalate", Success: false, Message: err.Error()}
			}
			return ActionResult{Action: "escalate", Success: true, Message: "Session escalated"}
		}

	case ActionSkip:
		return func() tea.Msg {
			err := m.client.InterveneSession(msg.SessionID, client.InterventionSkip, "manual skip via TUI")
			if err != nil {
				return ActionResult{Action: "skip", Success: false, Message: err.Error()}
			}
			return ActionResult{Action: "skip", Success: true, Message: "Stage skipped"}
		}

	case ActionAttach:
		return func() tea.Msg {
			tmuxSession, err := m.client.AttachSession(msg.SessionID)
			if err != nil {
				return ActionResult{Action: "attach", Success: false, Message: err.Error()}
			}
			if tmuxSession == "" {
				return ActionResult{Action: "attach", Success: false, Message: "no tmux session"}
			}
			attachCmd := exec.Command("tmux", "attach", "-t", tmuxSession)
			attachCmd.Stdin = os.Stdin
			attachCmd.Stdout = os.Stdout
			attachCmd.Stderr = os.Stderr
			if err := attachCmd.Run(); err != nil {
				return ActionResult{Action: "attach", Success: false, Message: err.Error()}
			}
			return ActionResult{Action: "attach", Success: true, Message: "Attached to " + tmuxSession}
		}

	case ActionRefresh:
		return m.fetchSessions()
	}

	return nil
}

func (m *AppModel) handleExecuteWorkflow(msg ExecuteWorkflowMsg) (tea.Model, tea.Cmd) {
	if m.client == nil {
		m.err = fmt.Errorf("no client connected")
		m.viewState = ViewNormal
		m.newSession = nil
		return m, nil
	}

	return m, func() tea.Msg {
		result, err := m.client.ExecuteWorkflowWithParams(msg.WorkflowID, msg.IssueID, msg.Variables)
		if err != nil {
			return errMsg{fmt.Errorf("failed to start workflow: %w", err)}
		}
		return NewSessionStartedMsg{
			SessionID:  result.SessionID,
			InstanceID: result.InstanceID,
			WorkflowID: result.WorkflowID,
		}
	}
}
