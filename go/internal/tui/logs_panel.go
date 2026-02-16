package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

type LogsPanel struct {
	viewport      viewport.Model
	logs          []LogEntry
	instance      *client.WorkflowInstance
	selectedStage int
	width         int
	height        int
	focused       bool
	expanded      bool
}

type LogEntry struct {
	Timestamp  time.Time
	StageID    string
	StageType  string
	EventType  string
	Input      string
	Output     string
	Error      string
	Validation []ValidationResult
	DurationMs int64
}

type ValidationResult struct {
	Type    string
	Status  string
	Message string
}

func NewLogsPanel() LogsPanel {
	vp := viewport.New(80, 20)
	vp.SetContent("")

	return LogsPanel{
		viewport:      vp,
		logs:          []LogEntry{},
		selectedStage: 0,
	}
}

func (l LogsPanel) Init() tea.Cmd {
	return nil
}

func (l *LogsPanel) SetInstance(instance *client.WorkflowInstance) {
	l.instance = instance
	if instance != nil {
		l.logs = l.buildLogsFromHistory(instance.ExecutionHistory)
	}
	l.updateViewport()
}

func (l *LogsPanel) buildLogsFromHistory(history []client.ExecutionHistoryItem) []LogEntry {
	logs := make([]LogEntry, 0, len(history))

	for _, item := range history {
		entry := LogEntry{
			StageID:    item.StageID,
			StageType:  item.StageType,
			Output:     item.Output,
			Error:      item.Error,
			DurationMs: item.DurationMs,
		}

		if item.StartedAt != "" {
			if t, err := time.Parse(time.RFC3339, item.StartedAt); err == nil {
				entry.Timestamp = t
			}
		}

		if item.Metadata != nil {
			if cmd, ok := item.Metadata["command"].(string); ok {
				entry.Input = cmd
				entry.EventType = "command"
			}
			if prompt, ok := item.Metadata["prompt"].(string); ok {
				entry.Input = prompt
				entry.EventType = "prompt"
			}
			if validations, ok := item.Metadata["validations"].([]interface{}); ok {
				entry.Validation = l.parseValidations(validations)
			}
		}

		if entry.EventType == "" {
			if entry.StageType == "agent" {
				entry.EventType = "prompt"
			} else if entry.StageType == "action" {
				entry.EventType = "command"
			}
		}

		logs = append(logs, entry)
	}

	return logs
}

func (l *LogsPanel) parseValidations(validations []interface{}) []ValidationResult {
	results := []ValidationResult{}
	for _, v := range validations {
		if vm, ok := v.(map[string]interface{}); ok {
			vr := ValidationResult{}
			if t, ok := vm["type"].(string); ok {
				vr.Type = t
			}
			if s, ok := vm["status"].(string); ok {
				vr.Status = s
			}
			if m, ok := vm["message"].(string); ok {
				vr.Message = m
			}
			results = append(results, vr)
		}
	}
	return results
}

func (l *LogsPanel) AddLogEntry(entry LogEntry) {
	l.logs = append(l.logs, entry)
	l.updateViewport()
}

func (l *LogsPanel) AddWSPayload(payload *client.WSPayload) {
	if payload == nil {
		return
	}

	entry := LogEntry{
		StageID:    payload.StageID,
		StageType:  payload.Type,
		EventType:  payload.Type,
		Input:      payload.Command,
		Output:     payload.Output,
		Error:      payload.Error,
		DurationMs: payload.DurationMs,
	}

	if payload.Timestamp != "" {
		if t, err := time.Parse(time.RFC3339, payload.Timestamp); err == nil {
			entry.Timestamp = t
		}
	}

	if payload.Prompt != "" {
		entry.Input = payload.Prompt
		entry.EventType = "prompt"
	}

	l.logs = append(l.logs, entry)
	l.updateViewport()
}

func (l *LogsPanel) updateViewport() {
	content := l.renderLogs()
	l.viewport.SetContent(content)
	l.viewport.GotoBottom()
}

func (l *LogsPanel) renderLogs() string {
	if len(l.logs) == 0 {
		return styles.Muted.Render("  No logs available")
	}

	var lines []string

	for i, entry := range l.logs {
		lines = append(lines, l.renderLogEntry(entry, i))
		lines = append(lines, "")
	}

	return strings.Join(lines, "\n")
}

func (l *LogsPanel) renderLogEntry(entry LogEntry, index int) string {
	var lines []string

	header := fmt.Sprintf("  [%d] %s", index+1, entry.StageID)
	if entry.StageType != "" {
		header += fmt.Sprintf(" (%s)", entry.StageType)
	}
	lines = append(lines, styles.Title.Render(header))

	if !entry.Timestamp.IsZero() {
		ts := entry.Timestamp.Format("15:04:05")
		lines = append(lines, styles.Muted.Render(fmt.Sprintf("      %s", ts)))
	}

	if entry.Input != "" {
		var label string
		var style lipgloss.Style
		if entry.EventType == "prompt" || entry.StageType == "agent" {
			label = "Prompt"
			style = lipgloss.NewStyle().Foreground(styles.Accent)
		} else {
			label = "Command"
			style = lipgloss.NewStyle().Foreground(styles.Warning)
		}
		lines = append(lines, fmt.Sprintf("    %s:", label))
		lines = append(lines, style.Render(fmt.Sprintf("      %s", truncateString(entry.Input, 80))))
	}

	if entry.Output != "" {
		lines = append(lines, "    Output:")
		outputLines := strings.Split(entry.Output, "\n")
		for _, ol := range outputLines {
			if ol != "" {
				lines = append(lines, fmt.Sprintf("      %s", truncateString(ol, 80)))
			}
		}
	}

	if len(entry.Validation) > 0 {
		lines = append(lines, "    Validations:")
		for _, v := range entry.Validation {
			var statusIcon string
			var statusStyle lipgloss.Style
			if v.Status == "passed" || v.Status == "success" {
				statusIcon = "✓"
				statusStyle = styles.StatusCompleted
			} else {
				statusIcon = "✗"
				statusStyle = styles.StatusFailed
			}
			line := fmt.Sprintf("      %s %s", statusIcon, v.Type)
			if v.Message != "" {
				line += fmt.Sprintf(": %s", v.Message)
			}
			lines = append(lines, statusStyle.Render(line))
		}
	}

	if entry.Error != "" {
		lines = append(lines, styles.StatusFailed.Render(fmt.Sprintf("    Error: %s", truncateString(entry.Error, 80))))
	}

	if entry.DurationMs > 0 {
		lines = append(lines, styles.Muted.Render(fmt.Sprintf("    Duration: %s", FormatDuration(entry.DurationMs))))
	}

	return strings.Join(lines, "\n")
}

func (l LogsPanel) View() string {
	boxStyle := styles.PanelInactive
	if l.focused {
		boxStyle = styles.PanelActive
	}

	title := " Detailed Logs "

	content := l.viewport.View()

	return lipgloss.JoinVertical(lipgloss.Left,
		styles.PanelHeader.Render(title),
		boxStyle.Render(content),
	)
}

func (l *LogsPanel) SetFocused(focused bool) {
	l.focused = focused
}

func (l *LogsPanel) SetSize(width, height int) {
	l.width = width - 4
	l.height = height - 4
	l.viewport.Width = l.width
	l.viewport.Height = l.height
}

func (l *LogsPanel) Clear() {
	l.logs = []LogEntry{}
	l.instance = nil
	l.viewport.SetContent("")
}

func (l *LogsPanel) ToggleExpanded() {
	l.expanded = !l.expanded
}

func (l *LogsPanel) SelectStage(index int) {
	if index >= 0 && index < len(l.logs) {
		l.selectedStage = index
	}
}

func FormatLogsFromInstance(instance *client.WorkflowInstance) string {
	panel := NewLogsPanel()
	panel.SetInstance(instance)
	return panel.renderLogs()
}
