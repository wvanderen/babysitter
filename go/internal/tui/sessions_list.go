package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	sessionTitleStyle = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230")).Padding(0, 1)
	selectedStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("170")).Bold(true)
	statusActiveStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	statusIdleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	statusDoneStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("86"))
	statusFailedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	helpStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	tableHeaderStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("241")).Bold(true)
	tableCellStyle    = lipgloss.NewStyle()
)

type SessionItem struct {
	ID       string
	IssueID  string
	Stage    string
	Status   string
	Duration string
}

func (s SessionItem) Title() string {
	return s.ID
}

func (s SessionItem) Description() string {
	return FormatStatus(s.Status)
}

func (s SessionItem) FilterValue() string {
	return s.ID + " " + s.IssueID
}

type SessionList struct {
	items    []SessionItem
	selected int
	focused  bool
	width    int
	height   int
}

func NewSessionList() SessionList {
	return SessionList{
		items:    []SessionItem{},
		selected: 0,
		focused:  true,
		width:    80,
		height:   20,
	}
}

type SessionListMsg struct {
	Sessions []SessionItem
}

func (s SessionList) Update(msg interface{}) (SessionList, error) {
	switch msg := msg.(type) {
	case SessionListMsg:
		s.items = msg.Sessions
		if s.selected >= len(s.items) {
			s.selected = 0
		}
	}
	return s, nil
}

func (s SessionList) View() string {
	borderColor := "62"
	if !s.focused {
		borderColor = "240"
	}
	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(borderColor)).
		Padding(0, 1)

	headerRow := tableHeaderStyle.Render("ID") + strings.Repeat(" ", 20) +
		tableHeaderStyle.Render("STATUS") + strings.Repeat(" ", 15) +
		tableHeaderStyle.Render("STARTED")

	if s.width < 10 {
		s.width = 80
	}

	var rows []string
	rows = append(rows, headerRow)
	rows = append(rows, strings.Repeat("─", max(0, s.width-2)))

	for i, item := range s.items {
		idCell := item.ID
		if len(idCell) > 20 {
			idCell = idCell[:17] + "..."
		}
		idCell = idCell + strings.Repeat(" ", max(0, 20-len(idCell)))

		statusCell := FormatStatus(item.Status)
		statusWidth := lipgloss.Width(statusCell)
		if statusWidth < 15 {
			statusCell = statusCell + strings.Repeat(" ", 15-statusWidth)
		}

		startedCell := item.Duration
		if startedCell == "" {
			startedCell = "-"
		}

		rowStyle := tableCellStyle
		if i == s.selected && s.focused {
			rowStyle = selectedStyle
		}

		row := rowStyle.Render(idCell) + rowStyle.Render(statusCell) + rowStyle.Render(startedCell)
		rows = append(rows, row)
	}

	for len(rows) < s.height-2 {
		rows = append(rows, strings.Repeat(" ", max(0, s.width-2)))
	}

	content := strings.Join(rows, "\n")

	return boxStyle.Render(content)
}

func (s SessionList) SelectedSession() *SessionItem {
	if s.selected >= 0 && s.selected < len(s.items) {
		return &s.items[s.selected]
	}
	return nil
}

func (s *SessionList) SetFocused(focused bool) {
	s.focused = focused
}

func (s *SessionList) SetSize(width, height int) {
	s.width = width
	s.height = height
}

func (s SessionList) HelpText() string {
	if s.focused {
		if s.selected >= 0 && s.selected < len(s.items) {
			return "[↑/↓] Select  [Enter] Output  [p] Pause  [r] Resume  [e] Escalate  [k] Skip  [a] Attach  [R] Refresh  [n] New  [q] Quit"
		}
		return "[↑/↓] Select  [n] New session  [q] Quit"
	}
	return "[Tab] Focus"
}

func FormatStatus(status string) string {
	switch strings.ToLower(status) {
	case "running", "active":
		return statusActiveStyle.Render("● " + status)
	case "idle", "pending":
		return statusIdleStyle.Render("○ " + status)
	case "completed", "success", "done":
		return statusDoneStyle.Render("✓ " + status)
	case "failed", "error":
		return statusFailedStyle.Render("✗ " + status)
	default:
		return status
	}
}
