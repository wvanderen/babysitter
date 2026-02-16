package ui

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

func RenderPill(text string, bg lipgloss.Color) string {
	style := lipgloss.NewStyle().
		Foreground(styles.TextInverse).
		Background(bg).
		Padding(0, 1)

	return style.Render(" " + text + " ")
}

func RenderPillWithStyle(text string, fg, bg lipgloss.Color, bold bool) string {
	style := lipgloss.NewStyle().
		Foreground(fg).
		Background(bg).
		Padding(0, 1)

	if bold {
		style = style.Bold(true)
	}

	return style.Render(" " + text + " ")
}

func RenderStatusPill(status string) string {
	var bg lipgloss.Color
	var text string

	switch status {
	case "running", "active":
		bg = styles.Info
		text = "● Running"
	case "completed", "success", "done":
		bg = styles.Success
		text = "✓ Done"
	case "failed", "error":
		bg = styles.Error
		text = "✗ Failed"
	case "idle", "pending":
		bg = styles.TextMuted
		text = "○ Idle"
	case "paused":
		bg = styles.Warning
		text = "⏸ Paused"
	default:
		bg = styles.TextMuted
		text = status
	}

	return RenderPill(text, bg)
}
