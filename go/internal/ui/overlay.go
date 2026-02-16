package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

func OverlayModal(background, modal string, width, height int) string {
	modalLines := strings.Split(modal, "\n")
	modalHeight := len(modalLines)
	modalWidth := 0
	for _, line := range modalLines {
		if w := lipgloss.Width(line); w > modalWidth {
			modalWidth = w
		}
	}

	startY := (height - modalHeight) / 2
	if startY < 0 {
		startY = 0
	}
	startX := (width - modalWidth) / 2
	if startX < 0 {
		startX = 0
	}

	bgLines := strings.Split(background, "\n")
	result := make([]string, len(bgLines))

	for i, line := range bgLines {
		if i < startY || i >= startY+modalHeight {
			result[i] = line
			continue
		}

		modalLineIdx := i - startY
		if modalLineIdx >= len(modalLines) {
			result[i] = line
			continue
		}

		modalLine := modalLines[modalLineIdx]
		lineRunes := []rune(line)

		if startX >= len(lineRunes) {
			result[i] = line
			continue
		}

		modalRunes := []rune(modalLine)
		endX := startX + len(modalRunes)
		if endX > len(lineRunes) {
			endX = len(lineRunes)
		}

		newLine := string(lineRunes[:startX]) + string(modalRunes[:min(len(modalRunes), endX-startX)])
		if endX < len(lineRunes) {
			newLine += string(lineRunes[endX:])
		}
		result[i] = newLine
	}

	return strings.Join(result, "\n")
}

func RenderModalBackground(width, height int) string {
	overlayStyle := lipgloss.NewStyle().
		Width(width).
		Height(height).
		Background(lipgloss.Color(string(styles.BgOverlay)))

	return overlayStyle.Render("")
}
