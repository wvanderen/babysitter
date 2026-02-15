package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
)

var (
	stageViewBoxStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(lipgloss.Color("62")).
				Padding(0, 1)

	stageViewTitleStyle = lipgloss.NewStyle().
				Background(lipgloss.Color("62")).
				Foreground(lipgloss.Color("230")).
				Padding(0, 1)
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
		return lipgloss.NewStyle().Faint(true).Render("  No active stage")
	}

	current := s.instance.CurrentStage
	if current == "" {
		return lipgloss.NewStyle().Faint(true).Render("  Workflow completed")
	}

	var stageType string
	for _, item := range s.history {
		if item.StageID == current {
			stageType = item.StageType
			break
		}
	}

	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("33"))
	stageLine := headerStyle.Render("  Current Stage: ") + current
	if stageType != "" {
		stageLine += lipgloss.NewStyle().Faint(true).Render(fmt.Sprintf(" (%s)", stageType))
	}

	statusLine := ""
	for _, item := range s.history {
		if item.StageID == current {
			statusLine = s.renderStageStatus(item)
			break
		}
	}
	if statusLine == "" {
		statusLine = stageRunningStyle.Render("  ● Running...")
	}

	return stageLine + "\n" + statusLine
}

func (s *StageView) renderStageStatus(item client.ExecutionHistoryItem) string {
	var lines []string

	statusIcon := "●"
	statusText := item.Status
	statusStyle := stageRunningStyle

	switch item.Status {
	case "completed", "success":
		statusIcon = "✓"
		statusStyle = stageCompletedStyle
		statusText = "Completed"
	case "failed", "failure":
		statusIcon = "✗"
		statusStyle = stageFailedStyle
		statusText = "Failed"
	case "skipped":
		statusIcon = "○"
		statusStyle = stageSkippedStyle
		statusText = "Skipped"
	case "running", "active":
		statusIcon = "●"
		statusStyle = stageRunningStyle
		statusText = "Running"
	}

	statusLine := statusStyle.Render(fmt.Sprintf("  %s %s", statusIcon, statusText))
	lines = append(lines, statusLine)

	if item.DurationMs > 0 {
		durationLine := lipgloss.NewStyle().Faint(true).Render(
			fmt.Sprintf("    Duration: %s", FormatDuration(item.DurationMs)),
		)
		lines = append(lines, durationLine)
	}

	if item.Error != "" {
		errorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
		errorLine := errorStyle.Render(fmt.Sprintf("    Error: %s", truncateString(item.Error, 60)))
		lines = append(lines, errorLine)
	}

	return strings.Join(lines, "\n")
}

func (s *StageView) renderHistory() string {
	if len(s.history) == 0 {
		return lipgloss.NewStyle().Faint(true).Render("  No execution history")
	}

	var lines []string
	lines = append(lines, lipgloss.NewStyle().Bold(true).Render("  Execution History:"))
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
		style = stageCompletedStyle
	case "failed", "failure":
		icon = "✗"
		style = stageFailedStyle
	case "skipped":
		icon = "○"
		style = stageSkippedStyle
	default:
		icon = "●"
		style = stageRunningStyle
	}

	var parts []string
	parts = append(parts, style.Render(fmt.Sprintf("  %d. %s %s", index, icon, item.StageID)))

	if item.StageType != "" {
		parts = append(parts, lipgloss.NewStyle().Faint(true).Render(fmt.Sprintf("[%s]", item.StageType)))
	}

	if item.DurationMs > 0 {
		parts = append(parts, lipgloss.NewStyle().Faint(true).Render(fmt.Sprintf("(%s)", FormatDuration(item.DurationMs))))
	}

	line := strings.Join(parts, " ")

	if item.Error != "" {
		errorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Faint(true)
		line += "\n" + errorStyle.Render(fmt.Sprintf("      └─ %s", truncateString(item.Error, 50)))
	}

	return line
}

func (s *StageView) renderRetryInfo() string {
	if s.instance == nil || s.instance.RetryCount == 0 {
		return ""
	}

	var lines []string
	lines = append(lines, "")
	lines = append(lines, lipgloss.NewStyle().Bold(true).Render("  Retry Information:"))

	retryLine := fmt.Sprintf("    Retries: %d / %d", s.instance.RetryCount, s.instance.MaxRetries)
	if s.instance.RetryCount >= s.instance.MaxRetries {
		retryLine = stageFailedStyle.Render(retryLine + " (max reached)")
	} else {
		retryLine = lipgloss.NewStyle().Faint(true).Render(retryLine)
	}
	lines = append(lines, retryLine)

	return strings.Join(lines, "\n")
}

func (s StageView) View() string {
	borderColor := "62"
	if !s.focused {
		borderColor = "240"
	}

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(borderColor)).
		Padding(0, 1)

	titleStyle := lipgloss.NewStyle().
		Background(lipgloss.Color(borderColor)).
		Foreground(lipgloss.Color("230")).
		Padding(0, 1)

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
		titleStyle.Render(title),
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

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

func FormatStageProgress(instance *client.WorkflowInstance) string {
	view := NewStageView()
	view.SetInstance(instance)
	return view.renderCurrentStage()
}
