package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

type LogDetailOverlay struct {
	entry        *LogEntry
	scrollOff    int
	width        int
	height       int
	contentLines []string
}

func NewLogDetailOverlay() LogDetailOverlay {
	return LogDetailOverlay{}
}

func (l *LogDetailOverlay) SetEntry(entry *LogEntry) {
	l.entry = entry
	l.scrollOff = 0
	l.contentLines = nil
	if entry != nil {
		l.contentLines = l.buildContentLines()
	}
}

func (l *LogDetailOverlay) buildContentLines() []string {
	if l.entry == nil {
		return nil
	}

	entry := l.entry
	var lines []string

	lines = append(lines, "")
	lines = append(lines, styles.Title.Render("  Log Detail"))
	lines = append(lines, "")

	stageID := entry.StageID
	if stageID == "" {
		stageID = "unknown"
	}
	lines = append(lines, fmt.Sprintf("  Stage: %s", stageID))

	if entry.StageType != "" {
		lines = append(lines, fmt.Sprintf("  Type: %s", entry.StageType))
	}

	var statusText string
	var statusStyle lipgloss.Style
	switch entry.Status {
	case "completed", "success":
		statusText = "success"
		statusStyle = styles.StatusCompleted
	case "failed", "failure":
		statusText = "failure"
		statusStyle = styles.StatusFailed
	case "running", "active":
		statusText = "running"
		statusStyle = styles.StatusRunning
	default:
		statusText = entry.Status
		statusStyle = styles.StatusPending
	}
	lines = append(lines, fmt.Sprintf("  Status: %s", statusStyle.Render(statusText)))

	if !entry.Timestamp.IsZero() {
		lines = append(lines, fmt.Sprintf("  Time: %s", entry.Timestamp.Format("15:04:05")))
	}

	if entry.DurationMs > 0 {
		lines = append(lines, fmt.Sprintf("  Duration: %s", FormatDuration(entry.DurationMs)))
	}

	lines = append(lines, "")

	if entry.Input != "" {
		label := "Command"
		if entry.EventType == "prompt" || entry.StageType == "agent" {
			label = "Prompt"
		}
		lines = append(lines, styles.Subtle.Render(fmt.Sprintf("  === %s ===", label)))
		inputLines := strings.Split(entry.Input, "\n")
		for _, il := range inputLines {
			lines = append(lines, fmt.Sprintf("  %s", il))
		}
		lines = append(lines, "")
	}

	if entry.Output != "" {
		lines = append(lines, styles.Subtle.Render("  === Output ==="))
		outputLines := strings.Split(entry.Output, "\n")
		for _, ol := range outputLines {
			if ol != "" {
				lines = append(lines, fmt.Sprintf("  %s", ol))
			} else {
				lines = append(lines, "")
			}
		}
		lines = append(lines, "")
	}

	if len(entry.Validation) > 0 {
		lines = append(lines, styles.Subtle.Render("  === Validations ==="))
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
			line := fmt.Sprintf("  %s %s", vIcon, v.Type)
			if v.Message != "" {
				line += fmt.Sprintf(": %s", v.Message)
			}
			lines = append(lines, vStyle.Render(line))
		}
		lines = append(lines, "")
	}

	if entry.Error != "" {
		lines = append(lines, styles.Subtle.Render("  === Error ==="))
		errorLines := strings.Split(entry.Error, "\n")
		for _, el := range errorLines {
			lines = append(lines, styles.StatusFailed.Render(fmt.Sprintf("  %s", el)))
		}
		lines = append(lines, "")
	}

	return lines
}

func (l *LogDetailOverlay) ScrollUp() {
	if l.scrollOff > 0 {
		l.scrollOff--
	}
}

func (l *LogDetailOverlay) ScrollDown() {
	maxScroll := len(l.contentLines) - l.viewportHeight()
	if maxScroll > 0 && l.scrollOff < maxScroll {
		l.scrollOff++
	}
}

func (l *LogDetailOverlay) ScrollHalfPageUp() {
	half := l.viewportHeight() / 2
	l.scrollOff -= half
	if l.scrollOff < 0 {
		l.scrollOff = 0
	}
}

func (l *LogDetailOverlay) ScrollHalfPageDown() {
	half := l.viewportHeight() / 2
	maxScroll := len(l.contentLines) - l.viewportHeight()
	l.scrollOff += half
	if l.scrollOff > maxScroll {
		l.scrollOff = maxScroll
	}
	if l.scrollOff < 0 {
		l.scrollOff = 0
	}
}

func (l *LogDetailOverlay) ScrollToTop() {
	l.scrollOff = 0
}

func (l *LogDetailOverlay) ScrollToBottom() {
	maxScroll := len(l.contentLines) - l.viewportHeight()
	if maxScroll > 0 {
		l.scrollOff = maxScroll
	} else {
		l.scrollOff = 0
	}
}

func (l *LogDetailOverlay) viewportHeight() int {
	h := l.height - 12
	if h < 5 {
		h = 5
	}
	return h
}

func (l LogDetailOverlay) Init() tea.Cmd {
	return nil
}

func (l LogDetailOverlay) Update(msg tea.Msg) (LogDetailOverlay, tea.Cmd) {
	return l, nil
}

func (l *LogDetailOverlay) SetSize(width, height int) {
	if width < 20 {
		width = 20
	}
	if height < 10 {
		height = 10
	}
	l.width = width
	l.height = height
}

func (l LogDetailOverlay) View() string {
	if l.entry == nil || len(l.contentLines) == 0 {
		return "No log entry selected"
	}

	if l.width < 20 || l.height < 10 {
		return "Window too small"
	}

	contentH := l.viewportHeight()

	var visibleLines []string
	end := l.scrollOff + contentH
	if end > len(l.contentLines) {
		end = len(l.contentLines)
	}

	for i := l.scrollOff; i < end; i++ {
		line := l.contentLines[i]
		visibleLines = append(visibleLines, line)
	}

	scrollInfo := ""
	if len(l.contentLines) > contentH {
		scrollInfo = styles.Muted.Render(fmt.Sprintf(" %d/%d ", l.scrollOff+1, len(l.contentLines)))
	}

	footer := styles.Muted.Render("[j/k] Scroll  [Ctrl+d/u] Half page  [g/G] Top/Bottom  [Esc] Close") + scrollInfo

	content := strings.Join(visibleLines, "\n")
	return content + "\n\n" + footer
}

func (l LogDetailOverlay) ViewWithOverlay() string {
	overlay := l.View()
	if overlay == "" {
		return ""
	}

	maxW := l.width - 8
	maxH := l.height - 4
	if maxW < 20 {
		maxW = 20
	}
	if maxH < 10 {
		maxH = 10
	}

	modalW := min(maxW, 80)
	modalH := min(maxH, 25)

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(styles.Accent).
		Padding(1, 2).
		Width(modalW).
		Height(modalH).
		MaxHeight(l.height - 2)

	centeredModal := lipgloss.NewStyle().
		Width(l.width).
		Height(l.height).
		Background(lipgloss.Color("#1e1e2e")).
		Align(lipgloss.Center, lipgloss.Center).
		Render(boxStyle.Render(overlay))

	return centeredModal
}
