package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

type WorkflowDiagram struct {
	workflow   *client.Workflow
	instance   *client.WorkflowInstance
	width      int
	height     int
	focused    bool
	stageOrder []string
}

func NewWorkflowDiagram() WorkflowDiagram {
	return WorkflowDiagram{
		stageOrder: []string{},
	}
}

func (d WorkflowDiagram) Init() interface{} {
	return nil
}

func (d *WorkflowDiagram) SetWorkflow(workflow *client.Workflow) {
	d.workflow = workflow
	d.stageOrder = d.buildStageOrder(workflow)
}

func (d *WorkflowDiagram) SetInstance(instance *client.WorkflowInstance) {
	d.instance = instance
}

func (d *WorkflowDiagram) buildStageOrder(workflow *client.Workflow) []string {
	if workflow == nil || len(workflow.Stages) == 0 {
		return []string{}
	}

	visited := make(map[string]bool)
	order := []string{}

	var visit func(stageID string)
	visit = func(stageID string) {
		if visited[stageID] {
			return
		}
		visited[stageID] = true
		order = append(order, stageID)

		if stage, ok := workflow.Stages[stageID]; ok {
			if stage.OnSuccess != "" {
				visit(stage.OnSuccess)
			}
			if stage.OnFailure != "" && stage.OnFailure != stage.OnSuccess {
				visit(stage.OnFailure)
			}
		}
	}

	for stageID := range workflow.Stages {
		if !visited[stageID] {
			visit(stageID)
			break
		}
	}

	if len(order) < len(workflow.Stages) {
		for stageID := range workflow.Stages {
			if !visited[stageID] {
				visited[stageID] = true
				order = append(order, stageID)
			}
		}
	}

	return order
}

func (d *WorkflowDiagram) getStageStatus(stageID string) string {
	if d.instance == nil {
		return "pending"
	}

	for _, item := range d.instance.ExecutionHistory {
		if item.StageID == stageID {
			return item.Status
		}
	}

	if d.instance.CurrentStage == stageID {
		return "running"
	}

	return "pending"
}

func (d *WorkflowDiagram) getStageTransition(stageID string) (string, string) {
	if d.workflow == nil {
		return "", ""
	}

	if stage, ok := d.workflow.Stages[stageID]; ok {
		return stage.OnSuccess, stage.OnFailure
	}
	return "", ""
}

func (d *WorkflowDiagram) renderStage(stageID string, status string) string {
	var icon string
	var style lipgloss.Style

	switch status {
	case "running":
		icon = "●"
		style = styles.StatusRunning
	case "completed", "success":
		icon = "✓"
		style = styles.StatusCompleted
	case "failed", "failure":
		icon = "✗"
		style = styles.StatusFailed
	case "skipped":
		icon = "○"
		style = styles.StatusSkipped
	default:
		icon = "○"
		style = styles.StatusPending
	}

	return style.Render(fmt.Sprintf("  %s %s", icon, stageID))
}

func (d *WorkflowDiagram) renderTransition(fromStage, toStage string, isFailure bool) string {
	var arrow string
	if isFailure {
		arrow = "  ├─[fail]→ "
	} else {
		arrow = "  └─[ok]→ "
	}
	return styles.Muted.Render(arrow) + styles.Subtle.Render(toStage)
}

func (d *WorkflowDiagram) renderDiagram() string {
	if d.workflow == nil {
		return styles.Muted.Render("  No workflow loaded")
	}

	var lines []string
	visited := make(map[string]bool)

	for _, stageID := range d.stageOrder {
		if visited[stageID] {
			continue
		}
		visited[stageID] = true

		status := d.getStageStatus(stageID)
		lines = append(lines, d.renderStage(stageID, status))

		onSuccess, onFailure := d.getStageTransition(stageID)

		if onFailure != "" && onFailure != onSuccess {
			lines = append(lines, d.renderTransition(stageID, onFailure, true))
		}
		if onSuccess != "" {
			lines = append(lines, d.renderTransition(stageID, onSuccess, false))
		}
	}

	return strings.Join(lines, "\n")
}

func (d *WorkflowDiagram) renderProgress() string {
	if d.instance == nil {
		return ""
	}

	completed := 0
	failed := 0
	for _, item := range d.instance.ExecutionHistory {
		if item.Status == "completed" || item.Status == "success" {
			completed++
		} else if item.Status == "failed" || item.Status == "failure" {
			failed++
		}
	}

	total := len(d.stageOrder)
	current := d.instance.CurrentStage

	var progressParts []string
	progressParts = append(progressParts, fmt.Sprintf("Progress: %d/%d stages", completed, total))
	if current != "" {
		progressParts = append(progressParts, fmt.Sprintf("Current: %s", current))
	}
	if failed > 0 {
		progressParts = append(progressParts, fmt.Sprintf("Failed: %d", failed))
	}

	return styles.Muted.Render("  " + strings.Join(progressParts, " | "))
}

func (d WorkflowDiagram) View() string {
	boxStyle := styles.PanelInactive
	if d.focused {
		boxStyle = styles.PanelActive
	}

	title := " Workflow Diagram "
	if d.workflow != nil && d.workflow.Name != "" {
		title = fmt.Sprintf(" %s ", d.workflow.Name)
	}

	diagram := d.renderDiagram()
	progress := d.renderProgress()

	var content string
	if progress != "" {
		content = diagram + "\n\n" + progress
	} else {
		content = diagram
	}

	return lipgloss.JoinVertical(lipgloss.Left,
		styles.PanelHeader.Render(title),
		boxStyle.Render(content),
	)
}

func (d *WorkflowDiagram) SetFocused(focused bool) {
	d.focused = focused
}

func (d *WorkflowDiagram) SetSize(width, height int) {
	d.width = width - 4
	d.height = height - 4
}

func (d *WorkflowDiagram) Clear() {
	d.workflow = nil
	d.instance = nil
	d.stageOrder = []string{}
}

func FormatWorkflowDiagram(workflow *client.Workflow, instance *client.WorkflowInstance) string {
	d := NewWorkflowDiagram()
	d.SetWorkflow(workflow)
	d.SetInstance(instance)
	return d.renderDiagram()
}
