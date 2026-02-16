package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/styles"
	"github.com/wvanderen/babysitter/go/internal/ui"
)

type StageView struct {
	instance *client.WorkflowInstance
	history  []client.ExecutionHistoryItem
	width    int
	height   int
	focused  bool
}

func NewStageView() StageView {
	return StageView{
		history: []client.ExecutionHistoryItem{},
	}
}

func (s StageView) Init() interface{} {
	return nil
}

func (s *StageView) SetInstance(instance *client.WorkflowInstance) {
	s.instance = instance
	if instance != nil {
		s.history = instance.ExecutionHistory
	}
}

func (s *StageView) SetHistory(history []client.ExecutionHistoryItem) {
	s.history = history
}

func (s *StageView) renderCurrentStage() string {
	if s.instance == nil {
		return styles.Muted.Render("  No active stage")
	}

	current := s.instance.CurrentStage
	if current == "" {
		return styles.Muted.Render("  Workflow completed")
	}

	var stageType string
	for _, item := range s.history {
		if item.StageID == current {
			stageType = item.StageType
			break
		}
	}

	stageLine := styles.Title.Render("  Current Stage: ") + current
	if stageType != "" {
		stageLine += styles.Muted.Render(fmt.Sprintf(" (%s)", stageType))
	}

	statusLine := ""
	for _, item := range s.history {
		if item.StageID == current {
			statusLine = s.renderStageStatus(item)
			break
		}
	}
	if statusLine == "" {
		statusLine = styles.StatusRunning.Render("  ● Running...")
	}

	return stageLine + "\n" + statusLine
}

func (s *StageView) renderStageStatus(item client.ExecutionHistoryItem) string {
	var lines []string

	statusIcon := "●"
	statusText := item.Status
	statusStyle := styles.StatusRunning

	switch item.Status {
	case "completed", "success":
		statusIcon = "✓"
		statusStyle = styles.StatusCompleted
		statusText = "Completed"
	case "failed", "failure":
		statusIcon = "✗"
		statusStyle = styles.StatusFailed
		statusText = "Failed"
	case "skipped":
		statusIcon = "○"
		statusStyle = styles.StatusSkipped
		statusText = "Skipped"
	case "running", "active":
		statusIcon = "●"
		statusStyle = styles.StatusRunning
		statusText = "Running"
	}

	statusLine := statusStyle.Render(fmt.Sprintf("  %s %s", statusIcon, statusText))
	lines = append(lines, statusLine)

	if item.DurationMs > 0 {
		durationLine := styles.Muted.Render(
			fmt.Sprintf("    Duration: %s", FormatDuration(item.DurationMs)),
		)
		lines = append(lines, durationLine)
	}

	if item.Error != "" {
		errorLine := styles.StatusFailed.Render(fmt.Sprintf("    Error: %s", ui.TruncateString(item.Error, 60)))
		lines = append(lines, errorLine)
	}

	return strings.Join(lines, "\n")
}

func (s *StageView) renderHistory() string {
	if len(s.history) == 0 {
		return styles.Muted.Render("  No execution history")
	}

	var lines []string
	lines = append(lines, styles.Title.Render("  Execution History:"))
	lines = append(lines, "")

	for i, item := range s.history {
		lines = append(lines, s.renderHistoryItem(item, i+1))
	}

	return strings.Join(lines, "\n")
}

func (s *StageView) renderHistoryItem(item client.ExecutionHistoryItem, index int) string {
	var icon string
	var style lipgloss.Style

	switch item.Status {
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
		icon = "●"
		style = styles.StatusRunning
	}

	var parts []string
	parts = append(parts, style.Render(fmt.Sprintf("  %d. %s %s", index, icon, item.StageID)))

	if item.StageType != "" {
		parts = append(parts, styles.Muted.Render(fmt.Sprintf("[%s]", item.StageType)))
	}

	if item.DurationMs > 0 {
		parts = append(parts, styles.Muted.Render(fmt.Sprintf("(%s)", FormatDuration(item.DurationMs))))
	}

	line := strings.Join(parts, " ")

	if item.Error != "" {
		line += "\n" + styles.StatusFailed.Render(fmt.Sprintf("      └─ %s", ui.TruncateString(item.Error, 50)))
	}

	return line
}

func (s *StageView) renderRetryInfo() string {
	if s.instance == nil || s.instance.RetryCount == 0 {
		return ""
	}

	var lines []string
	lines = append(lines, "")
	lines = append(lines, styles.Title.Render("  Retry Information:"))

	retryLine := fmt.Sprintf("    Retries: %d / %d", s.instance.RetryCount, s.instance.MaxRetries)
	if s.instance.RetryCount >= s.instance.MaxRetries {
		retryLine = styles.StatusFailed.Render(retryLine + " (max reached)")
	} else {
		retryLine = styles.Muted.Render(retryLine)
	}
	lines = append(lines, retryLine)

	return strings.Join(lines, "\n")
}

func (s StageView) View() string {
	boxStyle := styles.PanelInactive
	if s.focused {
		boxStyle = styles.PanelActive
	}

	title := " Stage Progress "

	var sections []string
	sections = append(sections, s.renderCurrentStage())

	if len(s.history) > 0 {
		sections = append(sections, "")
		sections = append(sections, s.renderHistory())
	}

	retryInfo := s.renderRetryInfo()
	if retryInfo != "" {
		sections = append(sections, retryInfo)
	}

	content := strings.Join(sections, "\n")

	return lipgloss.JoinVertical(lipgloss.Left,
		styles.PanelHeader.Render(title),
		boxStyle.Render(content),
	)
}

func (s *StageView) SetFocused(focused bool) {
	s.focused = focused
}

func (s *StageView) SetSize(width, height int) {
	s.width = width - 4
	s.height = height - 4
}

func (s *StageView) Clear() {
	s.instance = nil
	s.history = []client.ExecutionHistoryItem{}
}

func FormatStageProgress(instance *client.WorkflowInstance) string {
	view := NewStageView()
	view.SetInstance(instance)
	return view.renderCurrentStage()
}
