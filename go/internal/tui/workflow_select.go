package tui

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/modal"
)

type WorkflowSelect struct {
	modal       *modal.Modal
	workflows   []client.Workflow
	items       []modal.ListItem
	selectedIdx int
	err         error
	width       int
	height      int
}

func NewWorkflowSelect() WorkflowSelect {
	return WorkflowSelect{
		selectedIdx: 0,
		width:       50,
		height:      20,
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

func (w *WorkflowSelect) ensureModal() {
	w.items = make([]modal.ListItem, len(w.workflows))
	for i, wf := range w.workflows {
		w.items[i] = modal.ListItem{
			ID:    wf.ID,
			Label: wf.Name,
		}
	}

	w.modal = modal.New("Select Workflow",
		modal.WithWidth(50),
		modal.WithHints(true),
	).AddSection(modal.List("workflow", w.items, &w.selectedIdx,
		modal.WithMaxVisible(8),
	))
}

func (w WorkflowSelect) Update(msg tea.Msg) (WorkflowSelect, tea.Cmd) {
	switch msg := msg.(type) {
	case WorkflowSelectMsg:
		if msg.Err != nil {
			w.err = msg.Err
		} else if len(msg.Workflows) == 0 {
			w.err = fmt.Errorf("no workflows available")
		} else {
			w.err = nil
			w.workflows = msg.Workflows
			w.selectedIdx = 0
			w.ensureModal()
		}

	case tea.KeyMsg:
		if w.modal != nil {
			action, _ := w.modal.HandleKey(msg)
			switch action {
			case "cancel":
				return w, func() tea.Msg { return CancelWorkflowSelectMsg{} }
			default:
				if action != "" {
					for _, wf := range w.workflows {
						if wf.ID == action {
							return w, func() tea.Msg {
								return WorkflowSelectedMsg{Workflow: wf}
							}
						}
					}
				}
			}
		}
	}

	return w, nil
}

func (w WorkflowSelect) View() string {
	if w.err != nil {
		return "Error: " + w.err.Error()
	}

	if w.modal == nil {
		return "Loading workflows..."
	}

	hitMap := &modal.HitMap{}
	return w.modal.Render(w.width, w.height, hitMap)
}

func (w *WorkflowSelect) SetFocused(focused bool) {
}

func (w *WorkflowSelect) SetSize(width, height int) {
	w.width = width
	w.height = height
	if w.modal != nil {
		w.modal.SetWidth(min(50, width-4))
	}
}

type CancelWorkflowSelectMsg struct{}
