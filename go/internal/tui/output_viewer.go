package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/wvanderen/babysitter/go/internal/styles"
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
	boxStyle := styles.PanelInactive
	if o.focused {
		boxStyle = styles.PanelActive
	}

	title := styles.PanelHeader.Render(" " + o.title + " ")
	content := o.viewport.View()

	box := strings.Join([]string{title, boxStyle.Render(content)}, "\n")
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
