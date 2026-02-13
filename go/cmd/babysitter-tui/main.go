package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/tui"
)

type model struct {
	sessions []tui.Session
	quitting bool
}

func initialModel() model {
	return model{
		sessions: []tui.Session{},
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "r":
			return m, nil
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}

	s := "BABYSITTER TUI\n\n"

	if len(m.sessions) == 0 {
		s += "No active sessions.\n"
		s += "Connect to daemon at http://localhost:4001\n"
	} else {
		for _, sess := range m.sessions {
			s += fmt.Sprintf("  %s  %s  [%s]\n",
				sess.ID, sess.IssueID, sess.Stage)
		}
	}

	s += "\n[q] Quit  [r] Refresh\n"
	return s
}

func main() {
	p := tea.NewProgram(initialModel())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
