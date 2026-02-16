package ui

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

func RenderButton(text string, focused, hover bool) string {
	style := styles.ResolveButtonStyle(focused, hover, false)
	return style.Render(" " + text + " ")
}

func RenderDangerButton(text string, focused, hover bool) string {
	style := styles.ResolveButtonStyle(focused, hover, true)
	return style.Render(" " + text + " ")
}

func RenderButtonRow(buttons []string, selected int, focused bool) string {
	var rendered []string
	for i, btn := range buttons {
		rendered = append(rendered, RenderButton(btn, i == selected && focused, false))
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, rendered...)
}

func RenderButtonRowWithLabels(buttons []ButtonSpec, selected int, focused bool) string {
	var rendered []string
	for i, btn := range buttons {
		if btn.Danger {
			rendered = append(rendered, RenderDangerButton(btn.Label, i == selected && focused, false))
		} else {
			rendered = append(rendered, RenderButton(btn.Label, i == selected && focused, false))
		}
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, rendered...)
}

type ButtonSpec struct {
	Label  string
	Danger bool
	Action string
}
