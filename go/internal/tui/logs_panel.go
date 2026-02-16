package tui

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/client"
	"github.com/wvanderen/babysitter/go/internal/styles"
	"github.com/wvanderen/babysitter/go/internal/ui"
)

type LogsPanel struct {
	logs        []LogEntry
	instance    *client.WorkflowInstance
	selectedIdx int
	expanded    map[int]bool
	width       int
	height      int
	focused     bool
	scrollOff   int
}

type LogEntry struct {
	Timestamp  time.Time
	StageID    string
	StageType  string
	EventType  string
	Status     string
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
	return LogsPanel{
		logs:        []LogEntry{},
		expanded:    make(map[int]bool),
		selectedIdx: 0,
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
}

func (l *LogsPanel) buildLogsFromHistory(history []client.ExecutionHistoryItem) []LogEntry {
	logs := make([]LogEntry, 0, len(history))

	for _, item := range history {
		entry := LogEntry{
			StageID:    item.StageID,
			StageType:  item.StageType,
			Status:     item.Status,
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
}

func (l *LogsPanel) AddWSPayload(payload *client.WSPayload) {
	if payload == nil {
		return
	}

	entry := LogEntry{
		StageID:    payload.StageID,
		StageType:  payload.Type,
		EventType:  payload.Type,
		Status:     "completed",
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
}

func (l *LogsPanel) SelectUp() {
	if len(l.logs) == 0 {
		return
	}
	l.selectedIdx--
	if l.selectedIdx < 0 {
		l.selectedIdx = len(l.logs) - 1
	}
	l.ensureVisible()
}

func (l *LogsPanel) SelectDown() {
	if len(l.logs) == 0 {
		return
	}
	l.selectedIdx = (l.selectedIdx + 1) % len(l.logs)
	l.ensureVisible()
}

func (l *LogsPanel) ToggleExpand() {
	if len(l.logs) == 0 {
		return
	}
	l.expanded[l.selectedIdx] = !l.expanded[l.selectedIdx]
}

func (l *LogsPanel) ensureVisible() {
	visibleRows := l.visibleRowCount()
	if visibleRows < 1 {
		visibleRows = 1
	}

	if l.selectedIdx < l.scrollOff {
		l.scrollOff = l.selectedIdx
	}

	selectedRowInViewport := 0
	for i := 0; i < l.selectedIdx; i++ {
		if l.expanded[i] {
			selectedRowInViewport += l.expandedHeight(i)
		} else {
			selectedRowInViewport++
		}
	}

	scrollOffRows := 0
	for i := 0; i < l.scrollOff; i++ {
		if l.expanded[i] {
			scrollOffRows += l.expandedHeight(i)
		} else {
			scrollOffRows++
		}
	}

	if selectedRowInViewport < scrollOffRows {
		l.scrollOff = l.selectedIdx
		scrollOffRows = 0
		for i := 0; i < l.scrollOff; i++ {
			if l.expanded[i] {
				scrollOffRows += l.expandedHeight(i)
			} else {
				scrollOffRows++
			}
		}
	}

	if selectedRowInViewport >= scrollOffRows+visibleRows {
		for l.scrollOff < l.selectedIdx {
			l.scrollOff++
			scrollOffRows = 0
			for i := 0; i < l.scrollOff; i++ {
				if l.expanded[i] {
					scrollOffRows += l.expandedHeight(i)
				} else {
					scrollOffRows++
				}
			}
			if scrollOffRows <= selectedRowInViewport && selectedRowInViewport < scrollOffRows+visibleRows {
				break
			}
		}
	}
}

func (l *LogsPanel) expandedHeight(idx int) int {
	if !l.expanded[idx] {
		return 1
	}
	if idx >= len(l.logs) {
		return 1
	}
	entry := l.logs[idx]
	lines := 4
	if entry.Input != "" {
		lines += 2 + min(3, len(strings.Split(entry.Input, "\n")))
	}
	if entry.Output != "" {
		lines += 2 + min(5, len(strings.Split(entry.Output, "\n")))
	}
	if len(entry.Validation) > 0 {
		lines += 2 + len(entry.Validation)
	}
	if entry.Error != "" {
		lines += 2 + min(2, len(strings.Split(entry.Error, "\n")))
	}
	return lines
}

func (l *LogsPanel) visibleRowCount() int {
	return l.height - 4
}

func (l LogsPanel) View() string {
	if len(l.logs) == 0 {
		content := styles.Muted.Render("  No logs available")
		return styles.RenderPanel(" Detailed Logs ", content, l.focused, l.width, l.height)
	}

	var allRows []string
	for i := 0; i < len(l.logs); i++ {
		allRows = append(allRows, l.renderLogRow(i))
	}

	startRow := 0
	for i := 0; i < l.scrollOff && i < len(l.logs); i++ {
		if l.expanded[i] {
			startRow += l.expandedHeight(i)
		} else {
			startRow++
		}
	}

	visibleCount := l.visibleRowCount()
	visibleRows := []string{}
	rowCount := 0

	for i := l.scrollOff; i < len(l.logs) && rowCount < visibleCount; i++ {
		row := l.renderLogRow(i)
		lines := strings.Split(row, "\n")
		for _, line := range lines {
			if rowCount >= visibleCount {
				break
			}
			visibleRows = append(visibleRows, line)
			rowCount++
		}
	}

	content := strings.Join(visibleRows, "\n")
	return styles.RenderPanel(" Detailed Logs ", content, l.focused, l.width, l.height)
}

func (l LogsPanel) renderLogRow(idx int) string {
	entry := l.logs[idx]
	isSelected := idx == l.selectedIdx
	isExpanded := l.expanded[idx]

	expandIcon := "▸"
	if isExpanded {
		expandIcon = "▾"
	}

	var statusIcon string
	var statusStyle lipgloss.Style
	switch entry.Status {
	case "completed", "success":
		statusIcon = "✓"
		statusStyle = styles.StatusCompleted
	case "failed", "failure":
		statusIcon = "✗"
		statusStyle = styles.StatusFailed
	case "running", "active":
		statusIcon = "●"
		statusStyle = styles.StatusRunning
	case "skipped":
		statusIcon = "○"
		statusStyle = styles.StatusSkipped
	default:
		statusIcon = "○"
		statusStyle = styles.StatusPending
	}

	stageID := ui.TruncateString(entry.StageID, 20)
	stageType := ""
	if entry.StageType != "" {
		stageType = styles.Muted.Render(fmt.Sprintf("[%s]", entry.StageType))
	}

	rowStyle := styles.ListItemNormal
	if isSelected {
		rowStyle = styles.ListItemSelected
	}

	var duration string
	if entry.DurationMs > 0 {
		duration = styles.Muted.Render(FormatDuration(entry.DurationMs))
	}

	header := fmt.Sprintf("  %s %s %s", expandIcon, statusStyle.Render(statusIcon), stageID)
	if stageType != "" {
		header += " " + stageType
	}
	if duration != "" {
		header += " " + duration
	}

	header = rowStyle.Render(header)

	if !isExpanded {
		return header
	}

	var lines []string
	lines = append(lines, header)

	ts := ""
	if !entry.Timestamp.IsZero() {
		ts = entry.Timestamp.Format("15:04:05")
		lines = append(lines, styles.Muted.Render(fmt.Sprintf("      Time: %s", ts)))
	}

	if entry.Input != "" {
		label := "Input"
		if entry.EventType == "prompt" || entry.StageType == "agent" {
			label = "Prompt"
		}
		lines = append(lines, styles.Subtle.Render(fmt.Sprintf("      %s:", label)))
		inputLines := strings.Split(entry.Input, "\n")
		for i, il := range inputLines {
			if i >= 3 {
				lines = append(lines, styles.Muted.Render("      ..."))
				break
			}
			lines = append(lines, styles.Code.Render(fmt.Sprintf("        %s", ui.TruncateString(il, l.width-14))))
		}
	}

	if entry.Output != "" {
		lines = append(lines, styles.Subtle.Render("      Output:"))
		outputLines := strings.Split(entry.Output, "\n")
		for i, ol := range outputLines {
			if i >= 5 {
				lines = append(lines, styles.Muted.Render("      ..."))
				break
			}
			if ol != "" {
				lines = append(lines, fmt.Sprintf("        %s", ui.TruncateString(ol, l.width-14)))
			}
		}
	}

	if len(entry.Validation) > 0 {
		lines = append(lines, styles.Subtle.Render("      Validations:"))
		for _, v := range entry.Validation {
			var vIcon string
			var vStyle lipgloss.Style
			if v.Status == "passed" || v.Status == "success" {
				vIcon = "✓"
				vStyle = styles.StatusCompleted
			} else {
				vIcon = "✗"
				vStyle = styles.StatusFailed
			}
			line := fmt.Sprintf("        %s %s", vIcon, v.Type)
			if v.Message != "" {
				line += fmt.Sprintf(": %s", ui.TruncateString(v.Message, 40))
			}
			lines = append(lines, vStyle.Render(line))
		}
	}

	if entry.Error != "" {
		lines = append(lines, styles.StatusFailed.Render(fmt.Sprintf("      Error: %s", ui.TruncateString(entry.Error, l.width-14))))
	}

	return strings.Join(lines, "\n")
}

func (l *LogsPanel) SetFocused(focused bool) {
	l.focused = focused
}

func (l *LogsPanel) SetSize(width, height int) {
	l.width = width
	l.height = height
}

func (l *LogsPanel) Clear() {
	l.logs = []LogEntry{}
	l.instance = nil
	l.expanded = make(map[int]bool)
	l.selectedIdx = 0
	l.scrollOff = 0
}

func (l *LogsPanel) SelectedEntry() *LogEntry {
	if len(l.logs) == 0 || l.selectedIdx < 0 || l.selectedIdx >= len(l.logs) {
		return nil
	}
	return &l.logs[l.selectedIdx]
}

func FormatLogsFromInstance(instance *client.WorkflowInstance) string {
	panel := NewLogsPanel()
	panel.SetInstance(instance)
	return panel.View()
}
