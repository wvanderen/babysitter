package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	outputBoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62")).
			Padding(0, 1)

	outputTitleStyle = lipgloss.NewStyle().
				Background(lipgloss.Color("62")).
				Foreground(lipgloss.Color("230")).
				Padding(0, 1)
)

type OutputViewer struct {
	viewport viewport.Model
	output   []string
	title    string
	focused  bool
}

func NewOutputViewer() OutputViewer {
	vp := viewport.New(80, 20)
	vp.SetContent("")

	return OutputViewer{
		viewport: vp,
		output:   []string{},
		title:    "Output",
		focused:  false,
	}
}

func (o OutputViewer) Init() tea.Cmd {
	return nil
}

type OutputMsg struct {
	SessionID string
	Output    string
}

func (o OutputViewer) Update(msg tea.Msg) (OutputViewer, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case OutputMsg:
		o.AppendOutput(msg.Output)
	}

	if o.focused {
		o.viewport, cmd = o.viewport.Update(msg)
	}

	return o, cmd
}

func (o *OutputViewer) AppendOutput(output string) {
	lines := strings.Split(output, "\n")
	o.output = append(o.output, lines...)
	o.updateViewport()
}

func (o *OutputViewer) SetOutput(output []string) {
	o.output = output
	o.updateViewport()
}

func (o *OutputViewer) updateViewport() {
	content := strings.Join(o.output, "\n")
	o.viewport.SetContent(content)
	o.viewport.GotoBottom()
}

func (o OutputViewer) View() string {
	borderColor := "62"
	if !o.focused {
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

	title := titleStyle.Render(" " + o.title + " ")
	content := o.viewport.View()

	box := lipgloss.JoinVertical(lipgloss.Left,
		title,
		boxStyle.Render(content),
	)
	return box
}

func (o *OutputViewer) SetFocused(focused bool) {
	o.focused = focused
}

func (o *OutputViewer) SetSize(width, height int) {
	o.viewport.Width = width - 4
	o.viewport.Height = height - 4
}

func (o *OutputViewer) Clear() {
	o.output = []string{}
	o.viewport.SetContent("")
}
