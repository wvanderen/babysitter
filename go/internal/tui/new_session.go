package tui

import (
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	formTitleStyle = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230")).Padding(0, 1)
	formStyle      = lipgloss.NewStyle().Padding(1, 2)
	labelStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
)

type NewSession struct {
	workflowID   string
	workflowName string
	issueID      textinput.Model
	focused      bool
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
		focused:      true,
	}
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
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			issueID := n.issueID.Value()
			return n, func() tea.Msg {
				return ExecuteWorkflowMsg{
					WorkflowID: n.workflowID,
					IssueID:    issueID,
				}
			}
		case "esc":
			return n, func() tea.Msg { return NewSessionCanceledMsg{} }
		}
	}

	n.issueID, cmd = n.issueID.Update(msg)
	return n, cmd
}

func (n NewSession) View() string {
	title := "New Session: " + n.workflowName
	issueField := labelStyle.Render("Issue ID:") + " " + n.issueID.View()

	return formStyle.Render(
		formTitleStyle.Render(title) + "\n\n" +
			issueField + "\n\n" +
			helpStyle.Render("[Enter] Start  [Esc] Cancel"),
	)
}

func (n *NewSession) SetFocused(focused bool) {
	n.focused = focused
	if !focused {
		n.issueID.Blur()
	} else {
		n.issueID.Focus()
	}
}

func (n *NewSession) SetSize(width, height int) {
}
