package tui

import (
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/modal"
)

type NewSession struct {
	workflowID   string
	workflowName string
	issueID      textinput.Model
	modal        *modal.Modal
	width        int
	height       int
}

func NewNewSession(workflowID, workflowName string) NewSession {
	issueInput := textinput.New()
	issueInput.Placeholder = "td-123"
	issueInput.Focus()
	issueInput.Prompt = "Issue ID: "

	return NewSession{
		workflowID:   workflowID,
		workflowName: workflowName,
		issueID:      issueInput,
		width:        50,
		height:       20,
	}
}

func (n *NewSession) ensureModal() {
	n.modal = modal.New("New Session: "+n.workflowName,
		modal.WithWidth(50),
		modal.WithHints(true),
		modal.WithPrimaryAction("start"),
	).
		AddSection(modal.Text("Start a new workflow session")).
		AddSection(modal.Spacer()).
		AddSection(modal.InputWithLabel("issue", "Issue ID:", &n.issueID)).
		AddSection(modal.Spacer()).
		AddSection(modal.Buttons(
			modal.Btn(" Start ", "start"),
			modal.Btn(" Cancel ", "cancel"),
		))
}

func (n NewSession) Init() tea.Cmd {
	return nil
}

type NewSessionStartedMsg struct {
	SessionID  string
	InstanceID string
	WorkflowID string
}

type NewSessionCanceledMsg struct{}

func (n NewSession) Update(msg tea.Msg) (NewSession, tea.Cmd) {
	if n.modal == nil {
		n.ensureModal()
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		action, cmd := n.modal.HandleKey(msg)
		switch action {
		case "cancel":
			return n, func() tea.Msg { return NewSessionCanceledMsg{} }
		case "start", "issue":
			issueID := n.issueID.Value()
			return n, func() tea.Msg {
				return ExecuteWorkflowMsg{
					WorkflowID: n.workflowID,
					IssueID:    issueID,
				}
			}
		}
		return n, cmd
	}

	return n, nil
}

func (n NewSession) View() string {
	if n.modal == nil {
		n.ensureModal()
	}

	hitMap := &modal.HitMap{}
	return n.modal.Render(n.width, n.height, hitMap)
}

func (n *NewSession) SetFocused(focused bool) {
	if focused {
		n.issueID.Focus()
	} else {
		n.issueID.Blur()
	}
}

func (n *NewSession) SetSize(width, height int) {
	n.width = width
	n.height = height
	if n.modal != nil {
		n.modal.SetWidth(min(50, width-4))
	}
}
