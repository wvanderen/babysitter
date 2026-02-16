package modal

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
	"github.com/wvanderen/babysitter/go/internal/ui"
)

func (m *Modal) Render(screenW, screenH int, hitMap *HitMap) string {
	contentW := m.width - ModalPadding
	if contentW < 20 {
		contentW = 20
	}

	var renderedSections []RenderedSection
	m.focusIDs = nil

	for _, s := range m.sections {
		r := s.Render(contentW, m.currentFocusID(), "")
		if r.Height > 0 {
			renderedSections = append(renderedSections, r)
		}
		m.focusIDs = append(m.focusIDs, s.FocusableIDs()...)
	}

	if len(m.focusIDs) > 0 && m.focusIdx >= len(m.focusIDs) {
		m.focusIdx = 0
	}

	totalContentHeight := 0
	for _, r := range renderedSections {
		totalContentHeight += r.Height + 1
	}
	if totalContentHeight > 0 {
		totalContentHeight--
	}

	headerHeight := 2
	footerHeight := 0
	if m.showHints {
		footerHeight = 1
	}
	maxContentHeight := screenH - headerHeight - footerHeight - 4
	if maxContentHeight < 5 {
		maxContentHeight = 5
	}

	needsScrollbar := totalContentHeight > maxContentHeight
	viewportHeight := min(totalContentHeight, maxContentHeight)
	if needsScrollbar {
		contentW--
	}

	maxScroll := max(0, totalContentHeight-viewportHeight)
	if m.scrollOffset > maxScroll {
		m.scrollOffset = maxScroll
	}

	var contentLines []string
	lineIdx := 0
	for _, r := range renderedSections {
		lines := strings.Split(r.Content, "\n")
		for _, line := range lines {
			contentLines = append(contentLines, line)
			lineIdx++
		}
		if lineIdx < totalContentHeight {
			contentLines = append(contentLines, "")
			lineIdx++
		}
	}

	startLine := m.scrollOffset
	endLine := min(startLine+viewportHeight, len(contentLines))
	if startLine > len(contentLines) {
		startLine = 0
		endLine = min(viewportHeight, len(contentLines))
	}
	visibleLines := contentLines[startLine:endLine]

	for len(visibleLines) < viewportHeight {
		visibleLines = append(visibleLines, "")
	}

	content := strings.Join(visibleLines, "\n")

	if needsScrollbar {
		scrollbar := ui.RenderScrollbar(ui.ScrollbarParams{
			TotalItems:   totalContentHeight,
			ScrollOffset: m.scrollOffset,
			VisibleItems: viewportHeight,
			TrackHeight:  viewportHeight,
		})
		content = lipgloss.JoinHorizontal(lipgloss.Top, content, " ", scrollbar)
	}

	var borderColor lipgloss.Color
	switch m.variant {
	case VariantDanger:
		borderColor = styles.Error
	case VariantWarning:
		borderColor = styles.Warning
	case VariantInfo:
		borderColor = styles.Info
	default:
		borderColor = styles.BorderActive
	}

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Background(styles.BgSecondary).
		Padding(0, 2).
		Width(m.width - 4)

	titleStyle := lipgloss.NewStyle().
		Foreground(styles.TextPrimary).
		Bold(true).
		Padding(0, 1)

	title := titleStyle.Render(m.title)

	var body string
	if content != "" {
		body = title + "\n\n" + boxStyle.Render(content)
	} else {
		body = title + "\n" + boxStyle.Render("")
	}

	if m.showHints {
		hint := styles.Muted.Render("[Tab] Cycle  [Enter] Confirm  [Esc] Cancel")
		body = body + "\n" + hint
	}

	modalW := lipgloss.Width(body)
	modalH := lipgloss.Height(body)

	modalX := (screenW - modalW) / 2
	if modalX < 0 {
		modalX = 0
	}
	modalY := (screenH - modalH) / 2
	if modalY < 0 {
		modalY = 0
	}

	if hitMap != nil {
		hitMap.AddRect("modal-backdrop", 0, 0, screenW, screenH)

		bodyX := modalX
		bodyY := modalY + lipgloss.Height(title) + 2
		bodyW := modalW
		bodyH := viewportHeight
		hitMap.AddRect("modal-body", bodyX, bodyY, bodyW, bodyH)
	}

	return lipgloss.NewStyle().
		Width(screenW).
		Height(screenH).
		Align(lipgloss.Center, lipgloss.Center).
		Render(body)
}

func (m *Modal) RenderOverlay(screenW, screenH int, hitMap *HitMap) string {
	modal := m.Render(screenW, screenH, hitMap)

	bg := ui.RenderModalBackground(screenW, screenH)
	return ui.OverlayModal(bg, modal, screenW, screenH)
}

func (m *Modal) ScrollBy(delta int) {
	m.scrollOffset += delta
	m.cachedRender = ""
}

func (m *Modal) ScrollToTop() {
	m.scrollOffset = 0
	m.cachedRender = ""
}

func (m *Modal) ScrollToBottom() {
	m.scrollOffset = 999999
	m.cachedRender = ""
}
