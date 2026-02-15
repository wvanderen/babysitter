package tui

import (
	"fmt"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/marcus/babysitter/go/internal/client"
)

var (
	workflowTitleStyle = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230")).Padding(0, 1)
)

type WorkflowItem struct {
	ID   string
	Name string
}

func (w WorkflowItem) FilterValue() string {
	return w.ID + " " + w.Name
}

func (w WorkflowItem) Title() string       { return w.Name }
func (w WorkflowItem) Description() string { return w.ID }
func (w WorkflowItem) ShortString() string { return w.Name }

type WorkflowSelect struct {
	list     list.Model
	selected bool
	focused  bool
	err      error
}

func NewWorkflowSelect() WorkflowSelect {
	delegate := list.NewDefaultDelegate()
	delegate.SetHeight(1)
	delegate.SetSpacing(0)

	l := list.New([]list.Item{}, delegate, 40, 15)
	l.SetShowTitle(true)
	l.Title = "Select Workflow"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.Styles.Title = workflowTitleStyle

	return WorkflowSelect{
		list:    l,
		focused: true,
	}
}

func (w WorkflowSelect) Init() tea.Cmd {
	return nil
}

type WorkflowSelectMsg struct {
	Workflows []client.Workflow
	Err       error
}

type WorkflowSelectedMsg struct {
	Workflow client.Workflow
}

func (w WorkflowSelect) Update(msg tea.Msg) (WorkflowSelect, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case WorkflowSelectMsg:
		if msg.Err != nil {
			w.err = msg.Err
		} else if len(msg.Workflows) == 0 {
			w.err = fmt.Errorf("no workflows available")
		} else {
			w.err = nil
			items := make([]list.Item, len(msg.Workflows))
			for i, wf := range msg.Workflows {
				items[i] = WorkflowItem{ID: wf.ID, Name: wf.Name}
			}
			w.list.SetItems(items)
		}

	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			if item, ok := w.list.SelectedItem().(WorkflowItem); ok {
				w.selected = true
				return w, func() tea.Msg {
					return WorkflowSelectedMsg{Workflow: client.Workflow{ID: item.ID, Name: item.Name}}
				}
			}
		case "esc":
			w.selected = true
			return w, func() tea.Msg { return CancelWorkflowSelectMsg{} }
		}
	}

	if w.focused {
		w.list, cmd = w.list.Update(msg)
	}

	return w, cmd
}

func (w WorkflowSelect) View() string {
	if w.err != nil {
		return w.list.View() + "\n\nError: " + w.err.Error()
	}
	return w.list.View()
}

func (w *WorkflowSelect) SetFocused(focused bool) {
	w.focused = focused
}

func (w *WorkflowSelect) SetSize(width, height int) {
	w.list.SetSize(width, height)
}

type CancelWorkflowSelectMsg struct{}
