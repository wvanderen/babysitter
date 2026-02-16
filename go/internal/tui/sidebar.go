package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/modal"
	"github.com/wvanderen/babysitter/go/internal/styles"
	"github.com/wvanderen/babysitter/go/internal/ui"
)

type Sidebar struct {
	sessions  []SessionItem
	selected  int
	focused   bool
	width     int
	height    int
	scrollOff int
	hitMap    *modal.HitMap
	renderedY int
}

func NewSidebar() Sidebar {
	return Sidebar{
		sessions: []SessionItem{},
		selected: 0,
		focused:  true,
		width:    30,
		height:   20,
		hitMap:   &modal.HitMap{},
	}
}

func (s *Sidebar) SetSessions(sessions []SessionItem) {
	s.sessions = sessions
	if s.selected >= len(s.sessions) {
		s.selected = 0
	}
}

func (s *Sidebar) SelectedSession() *SessionItem {
	if s.selected >= 0 && s.selected < len(s.sessions) {
		return &s.sessions[s.selected]
	}
	return nil
}

func (s *Sidebar) SetFocused(focused bool) {
	s.focused = focused
}

func (s *Sidebar) SetSize(width, height int) {
	s.width = width
	s.height = height
}

func (s *Sidebar) SelectUp() {
	if len(s.sessions) == 0 {
		return
	}
	s.selected--
	if s.selected < 0 {
		s.selected = len(s.sessions) - 1
	}
	s.ensureVisible()
}

func (s *Sidebar) SelectDown() {
	if len(s.sessions) == 0 {
		return
	}
	s.selected = (s.selected + 1) % len(s.sessions)
	s.ensureVisible()
}

func (s *Sidebar) ensureVisible() {
	visibleItems := s.height - 4
	if visibleItems < 1 {
		visibleItems = 1
	}

	if s.selected < s.scrollOff {
		s.scrollOff = s.selected
	}
	if s.selected >= s.scrollOff+visibleItems {
		s.scrollOff = s.selected - visibleItems + 1
	}

	maxScroll := max(0, len(s.sessions)-visibleItems)
	if s.scrollOff > maxScroll {
		s.scrollOff = maxScroll
	}
}

func (s Sidebar) View() string {
	boxStyle := styles.PanelInactive
	if s.focused {
		boxStyle = styles.PanelActive
	}

	var lines []string
	lines = append(lines, styles.PanelHeader.Render(" Sessions "))
	lines = append(lines, "")

	visibleItems := s.height - 4
	if visibleItems < 1 {
		visibleItems = 1
	}

	if len(s.sessions) == 0 {
		lines = append(lines, styles.Muted.Render("  No sessions"))
	} else {
		end := min(s.scrollOff+visibleItems, len(s.sessions))
		for i := s.scrollOff; i < end; i++ {
			session := s.sessions[i]
			isSelected := i == s.selected

			style := styles.ListItemNormal
			if isSelected && s.focused {
				style = styles.ListItemSelected
			}

			statusIcon := "○"
			switch strings.ToLower(session.Status) {
			case "running", "active":
				statusIcon = styles.StatusRunning.Render("●")
			case "completed", "success", "done":
				statusIcon = styles.StatusCompleted.Render("✓")
			case "failed", "error":
				statusIcon = styles.StatusFailed.Render("✗")
			}

			id := ui.TruncateString(session.ID, s.width-6)

			line := style.Render("  " + statusIcon + " " + id)
			lines = append(lines, line)
		}
	}

	for len(lines) < s.height-2 {
		lines = append(lines, "")
	}

	content := strings.Join(lines, "\n")
	return boxStyle.Render(content)
}

func (s Sidebar) HelpText() string {
	if s.focused {
		return "[↑/↓] Navigate  [n] New  [a] Attach  [q] Quit"
	}
	return "[Tab] Focus sidebar"
}

func (s *Sidebar) SetRenderPosition(y int) {
	s.renderedY = y
}

func (s *Sidebar) ViewWithHitRegions() string {
	s.hitMap.Clear()

	boxStyle := styles.PanelInactive
	if s.focused {
		boxStyle = styles.PanelActive
	}

	var lines []string
	lines = append(lines, styles.PanelHeader.Render(" Sessions "))
	lines = append(lines, "")

	visibleItems := s.height - 4
	if visibleItems < 1 {
		visibleItems = 1
	}

	itemStartY := 2

	if len(s.sessions) == 0 {
		lines = append(lines, styles.Muted.Render("  No sessions"))
	} else {
		end := min(s.scrollOff+visibleItems, len(s.sessions))
		for i := s.scrollOff; i < end; i++ {
			session := s.sessions[i]
			isSelected := i == s.selected

			style := styles.ListItemNormal
			if isSelected && s.focused {
				style = styles.ListItemSelected
			}

			statusIcon := "○"
			switch strings.ToLower(session.Status) {
			case "running", "active":
				statusIcon = styles.StatusRunning.Render("●")
			case "completed", "success", "done":
				statusIcon = styles.StatusCompleted.Render("✓")
			case "failed", "error":
				statusIcon = styles.StatusFailed.Render("✗")
			}

			id := ui.TruncateString(session.ID, s.width-6)

			line := style.Render("  " + statusIcon + " " + id)
			lines = append(lines, line)

			lineY := s.renderedY + itemStartY + (i - s.scrollOff)
			s.hitMap.AddRect("session-"+session.ID, 0, lineY, s.width, 1)
		}
	}

	for len(lines) < s.height-2 {
		lines = append(lines, "")
	}

	content := strings.Join(lines, "\n")
	return boxStyle.Render(content)
}

func (s *Sidebar) HandleMouse(msg tea.MouseMsg) string {
	if s.hitMap == nil {
		return ""
	}

	var action modal.MouseAction
	switch msg.Type {
	case tea.MouseLeft:
		action = modal.ActionClick
	case tea.MouseRelease:
		return ""
	case tea.MouseWheelUp:
		s.SelectUp()
		return "scroll"
	case tea.MouseWheelDown:
		s.SelectDown()
		return "scroll"
	default:
		return ""
	}

	mouseMsg := modal.MouseMsg{
		Action: action,
		X:      msg.X,
		Y:      msg.Y,
	}

	region := s.hitMap.Test(mouseMsg.X, mouseMsg.Y)
	if region == nil {
		return ""
	}

	mouseMsg.Region = region

	if region.ID == "sidebar" {
		return ""
	}

	if len(region.ID) > 8 && region.ID[:8] == "session-" {
		sessionID := region.ID[8:]
		for i, session := range s.sessions {
			if session.ID == sessionID {
				s.selected = i
				s.ensureVisible()
				return "select:" + sessionID
			}
		}
	}

	return ""
}
