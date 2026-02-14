package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	sessionStyle      = lipgloss.NewStyle().Padding(0, 2)
	selectedStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("170")).Bold(true)
	statusActiveStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
	statusIdleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	statusDoneStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("86"))
	statusFailedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	titleStyle        = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230")).Padding(0, 1)
	helpStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
)

type SessionItem struct {
	ID       string
	IssueID  string
	Stage    string
	Status   string
	Duration string
}

func (s SessionItem) FilterValue() string {
	return s.ID + " " + s.IssueID
}

type SessionList struct {
	list     list.Model
	selected int
	focused  bool
}

func NewSessionList() SessionList {
	delegate := list.NewDefaultDelegate()
	delegate.SetHeight(1)
	delegate.SetSpacing(0)

	l := list.New([]list.Item{}, delegate, 40, 20)
	l.SetShowTitle(true)
	l.Title = "Sessions"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.Styles.Title = titleStyle

	return SessionList{
		list:    l,
		focused: true,
	}
}

func (s SessionList) Init() tea.Cmd {
	return nil
}

type SessionListMsg struct {
	Sessions []SessionItem
}

func (s SessionList) Update(msg tea.Msg) (SessionList, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case SessionListMsg:
		items := make([]list.Item, len(msg.Sessions))
		for i, sess := range msg.Sessions {
			items[i] = sess
		}
		s.list.SetItems(items)
	}

	if s.focused {
		s.list, cmd = s.list.Update(msg)
	}

	return s, cmd
}

func (s SessionList) View() string {
	return s.list.View()
}

func (s SessionList) SelectedSession() *SessionItem {
	if item, ok := s.list.SelectedItem().(SessionItem); ok {
		return &item
	}
	return nil
}

func (s *SessionList) SetFocused(focused bool) {
	s.focused = focused
}

func (s *SessionList) SetSize(width, height int) {
	s.list.SetSize(width, height)
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
