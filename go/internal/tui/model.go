package tui

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/keymap"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

type FocusArea int

const (
	FocusSidebar FocusArea = iota
	FocusWorkflowDiagram
	FocusLogsPanel
)

type ViewState int

const (
	ViewNormal ViewState = iota
	ViewWorkflowSelect
	ViewNewSession
)

var (
	appStyle = lipgloss.NewStyle().Padding(1, 2)

	sidebarWidth = 28
)

type AppModel struct {
	sidebar         Sidebar
	workflowDiagram WorkflowDiagram
	logsPanel       LogsPanel
	outputViewer    OutputViewer
	workflowSelect  WorkflowSelect
	newSession      *NewSession
	focus           FocusArea
	viewState       ViewState
	client          *client.Client
	wsClient        *client.WSClient
	sessions        []client.Session
	currentInstance *client.WorkflowInstance
	currentWorkflow *client.Workflow
	connected       bool
	quitting        bool
	err             error
	width           int
	height          int
}

func NewAppModel(apiClient *client.Client) AppModel {
	return AppModel{
		sidebar:         NewSidebar(),
		workflowDiagram: NewWorkflowDiagram(),
		logsPanel:       NewLogsPanel(),
		outputViewer:    NewOutputViewer(),
		workflowSelect:  NewWorkflowSelect(),
		focus:           FocusSidebar,
		viewState:       ViewNormal,
		client:          apiClient,
		sessions:        []client.Session{},
		connected:       false,
		quitting:        false,
		width:           120,
		height:          40,
	}
}

func (m AppModel) Init() tea.Cmd {
	return tea.Batch(
		m.outputViewer.Init(),
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
				ID:     s.ID,
				Status: s.Status,
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

func (m AppModel) fetchInstance(sessionID string) tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return nil
		}
		session, err := m.client.GetSession(sessionID)
		if err != nil {
			return nil
		}
		if session.WorkflowInstance == nil {
			return nil
		}
		instance := session.WorkflowInstance
		workflow, err := m.client.GetWorkflow(instance.WorkflowID)
		if err != nil {
			return InstanceLoadedMsg{Instance: instance, Workflow: nil}
		}
		return InstanceLoadedMsg{Instance: instance, Workflow: workflow}
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

type InstanceLoadedMsg struct {
	Instance *client.WorkflowInstance
	Workflow *client.Workflow
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
		case "up", "k":
			if m.focus == FocusSidebar {
				m.sidebar.SelectUp()
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.fetchInstance(selected.ID))
				}
			} else if m.focus == FocusLogsPanel {
				m.logsPanel.SelectUp()
			}
		case "down", "j":
			if m.focus == FocusSidebar {
				m.sidebar.SelectDown()
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.fetchInstance(selected.ID))
				}
			} else if m.focus == FocusLogsPanel {
				m.logsPanel.SelectDown()
			}
		case "enter", " ":
			if m.focus == FocusLogsPanel {
				m.logsPanel.ToggleExpand()
			}
		case "p":
			if m.focus == FocusSidebar {
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.handleControlAction(ControlMsg{Action: ActionPause, SessionID: selected.ID}))
				}
			}
		case "r":
			if m.focus == FocusSidebar {
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.handleControlAction(ControlMsg{Action: ActionResume, SessionID: selected.ID}))
				}
			}
		case "e":
			if m.focus == FocusSidebar {
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.handleControlAction(ControlMsg{Action: ActionEscalate, SessionID: selected.ID}))
				}
			}
		case "s":
			if m.focus == FocusSidebar {
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.handleControlAction(ControlMsg{Action: ActionSkip, SessionID: selected.ID}))
				}
			}
		case "a":
			if m.focus == FocusSidebar {
				if selected := m.sidebar.SelectedSession(); selected != nil {
					cmds = append(cmds, m.handleControlAction(ControlMsg{Action: ActionAttach, SessionID: selected.ID}))
				}
			}
		case "R":
			if m.focus == FocusSidebar {
				cmds = append(cmds, m.fetchSessions())
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.handleResize()

	case tea.MouseMsg:
		action := m.sidebar.HandleMouse(msg)
		if action != "" {
			if len(action) > 7 && action[:7] == "select:" {
				sessionID := action[7:]
				cmds = append(cmds, m.fetchInstance(sessionID))
			}
			m.focus = FocusSidebar
			m.sidebar.SetFocused(true)
		}

	case SessionListMsg:
		m.sidebar.SetSessions(msg.Sessions)
		if len(msg.Sessions) > 0 {
			selected := m.sidebar.SelectedSession()
			if selected != nil {
				cmds = append(cmds, m.fetchInstance(selected.ID))
			}
		}

	case InstanceLoadedMsg:
		m.currentInstance = msg.Instance
		m.currentWorkflow = msg.Workflow
		m.workflowDiagram.SetWorkflow(msg.Workflow)
		m.workflowDiagram.SetInstance(msg.Instance)
		m.logsPanel.SetInstance(msg.Instance)

	case errMsg:
		m.err = msg

	case client.WSMessage:
		if cmd := m.handleWSMessage(msg); cmd != nil {
			cmds = append(cmds, cmd)
		}

	case FocusMsg:
		m.focus = msg.Area
		m.sidebar.SetFocused(m.focus == FocusSidebar)
		m.workflowDiagram.SetFocused(m.focus == FocusWorkflowDiagram)
		m.logsPanel.SetFocused(m.focus == FocusLogsPanel)
		m.outputViewer.SetFocused(m.focus == FocusLogsPanel)

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

	case ActionResult:
		if msg.Success {
			cmds = append(cmds, m.fetchSessions())
		}
	}

	var cmd tea.Cmd
	m.outputViewer, cmd = m.outputViewer.Update(msg)
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

	return m, tea.Batch(cmds...)
}

func (m *AppModel) handleResize() {
	h, v := appStyle.GetFrameSize()
	contentW := m.width - h
	contentH := m.height - v - 4

	sbW := min(sidebarWidth, contentW/4)
	mainW := contentW - sbW - 3

	m.sidebar.SetSize(sbW, contentH)

	topHalfH := contentH / 2
	bottomHalfH := contentH - topHalfH

	m.workflowDiagram.SetSize(mainW, topHalfH)
	m.logsPanel.SetSize(mainW, bottomHalfH)
	m.outputViewer.SetSize(mainW, 6)
}

func (m *AppModel) cycleFocus() {
	switch m.focus {
	case FocusSidebar:
		m.focus = FocusWorkflowDiagram
	case FocusWorkflowDiagram:
		m.focus = FocusLogsPanel
	case FocusLogsPanel:
		m.focus = FocusSidebar
	}
	m.sidebar.SetFocused(m.focus == FocusSidebar)
	m.workflowDiagram.SetFocused(m.focus == FocusWorkflowDiagram)
	m.logsPanel.SetFocused(m.focus == FocusLogsPanel)
}

func (m *AppModel) cycleFocusBack() {
	m.cycleFocus()
}

func (m *AppModel) handleWSMessage(msg client.WSMessage) tea.Cmd {
	switch msg.Event {
	case "session:output":
		if msg.Payload != nil {
			m.outputViewer.AppendOutput(msg.Payload.Output)
		}
	case "stage:started":
		if msg.Payload != nil {
			m.logsPanel.AddWSPayload(msg.Payload)
		}
		if selected := m.sidebar.SelectedSession(); selected != nil {
			return m.fetchInstance(selected.ID)
		}
	case "stage:completed":
		if msg.Payload != nil {
			m.logsPanel.AddWSPayload(msg.Payload)
		}
		if selected := m.sidebar.SelectedSession(); selected != nil {
			return m.fetchInstance(selected.ID)
		}
	case "stage:transition", "workflow:progress":
		if selected := m.sidebar.SelectedSession(); selected != nil {
			return m.fetchInstance(selected.ID)
		}
	case "session:started", "session:status":
		return m.fetchSessions()
	}
	return nil
}

func (m AppModel) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}

	switch m.viewState {
	case ViewWorkflowSelect:
		header := styles.Title.Render("BABYSITTER") + "  " +
			styles.Muted.Render("[Enter] Select  [Esc] Cancel  [q] Quit")
		return appStyle.Render(
			lipgloss.JoinVertical(lipgloss.Left,
				header,
				"",
				m.workflowSelect.View(),
			),
		)

	case ViewNewSession:
		header := styles.Title.Render("BABYSITTER") + "  " +
			styles.Muted.Render("[Enter] Start  [Esc] Cancel  [q] Quit")
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
		errView = styles.StatusFailed.Render(fmt.Sprintf("Error: %v", m.err))
	}

	_, v := appStyle.GetFrameSize()
	sidebarY := v + 2
	m.sidebar.SetRenderPosition(sidebarY)
	sidebar := m.sidebar.ViewWithHitRegions()

	diagramPanel := m.workflowDiagram.View()
	logsPanel := m.logsPanel.View()

	mainContent := lipgloss.JoinVertical(lipgloss.Left,
		diagramPanel,
		logsPanel,
	)

	layout := lipgloss.JoinHorizontal(lipgloss.Top,
		sidebar,
		"  ",
		mainContent,
	)

	header := styles.Title.Render("BABYSITTER")

	context := "main"
	if m.focus == FocusSidebar {
		context = "sidebar"
	}
	cmds := keymap.CommandsForContext(context)
	if m.focus == FocusLogsPanel {
		cmds = append(cmds, keymap.Command{ID: "logs-up", Name: "Up", Key: "↑", Priority: 2})
		cmds = append(cmds, keymap.Command{ID: "logs-down", Name: "Down", Key: "↓", Priority: 2})
		cmds = append(cmds, keymap.Command{ID: "logs-expand", Name: "Expand", Key: "Enter", Priority: 3})
	}
	helpBar := styles.KeyHint.Render(keymap.RenderHints(cmds, m.width-4))

	return appStyle.Render(
		lipgloss.JoinVertical(lipgloss.Left,
			header,
			"",
			layout,
			"",
			helpBar,
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
