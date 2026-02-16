package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

type ScrollbarParams struct {
	TotalItems   int
	ScrollOffset int
	VisibleItems int
	TrackHeight  int
}

func RenderScrollbar(params ScrollbarParams) string {
	if params.TrackHeight < 1 {
		return ""
	}

	if params.TotalItems <= params.VisibleItems {
		return strings.Repeat(" \n", params.TrackHeight-1) + " "
	}

	scrollableRange := params.TotalItems - params.VisibleItems
	thumbSize := max(1, (params.VisibleItems*params.TrackHeight)/params.TotalItems)
	thumbSize = min(thumbSize, params.TrackHeight-1)

	thumbPos := 0
	if scrollableRange > 0 {
		thumbPos = (params.ScrollOffset * (params.TrackHeight - thumbSize)) / scrollableRange
	}
	thumbPos = max(0, min(thumbPos, params.TrackHeight-thumbSize))

	trackStyle := lipgloss.NewStyle().Foreground(styles.ScrollbarTrackColor)
	thumbStyle := lipgloss.NewStyle().Foreground(styles.ScrollbarThumbColor)

	var lines []string
	for i := 0; i < params.TrackHeight; i++ {
		if i >= thumbPos && i < thumbPos+thumbSize {
			lines = append(lines, thumbStyle.Render("┃"))
		} else {
			lines = append(lines, trackStyle.Render("│"))
		}
	}

	return strings.Join(lines, "\n")
}
