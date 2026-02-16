package modal

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
	"github.com/wvanderen/babysitter/go/internal/ui"
)

type RenderedSection struct {
	Content    string
	Height     int
	Focusables []FocusableInfo
}

type FocusableInfo struct {
	ID       string
	Y        int
	Height   int
	IsButton bool
}

type Section interface {
	Render(contentWidth int, focusID, hoverID string) RenderedSection
	FocusableIDs() []string
}

type textSection struct {
	text string
}

func Text(s string) Section {
	return &textSection{text: s}
}

func (t *textSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	lines := strings.Split(t.text, "\n")
	var wrapped []string
	for _, line := range lines {
		if len(line) <= contentWidth {
			wrapped = append(wrapped, line)
		} else {
			for len(line) > contentWidth {
				wrapped = append(wrapped, line[:contentWidth])
				line = line[contentWidth:]
			}
			if line != "" {
				wrapped = append(wrapped, line)
			}
		}
	}
	return RenderedSection{
		Content: strings.Join(wrapped, "\n"),
		Height:  len(wrapped),
	}
}

func (t *textSection) FocusableIDs() []string {
	return nil
}

type spacerSection struct{}

func Spacer() Section {
	return &spacerSection{}
}

func (s *spacerSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	return RenderedSection{Content: "", Height: 1}
}

func (s *spacerSection) FocusableIDs() []string {
	return nil
}

type ButtonDef struct {
	Label    string
	ID       string
	IsDanger bool
}

type BtnOption func(*ButtonDef)

func BtnDanger() BtnOption {
	return func(b *ButtonDef) { b.IsDanger = true }
}

func Btn(label, id string, opts ...BtnOption) ButtonDef {
	b := ButtonDef{Label: label, ID: id}
	for _, opt := range opts {
		opt(&b)
	}
	return b
}

type buttonsSection struct {
	buttons []ButtonDef
}

func Buttons(btns ...ButtonDef) Section {
	return &buttonsSection{buttons: btns}
}

func (b *buttonsSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	var rendered []string
	var focusables []FocusableInfo
	x := 0

	for _, btn := range b.buttons {
		focused := focusID == btn.ID
		style := styles.ResolveButtonStyle(focused, false, btn.IsDanger)
		renderedBtn := style.Render(" " + btn.Label + " ")
		rendered = append(rendered, renderedBtn)

		btnWidth := lipgloss.Width(renderedBtn)
		focusables = append(focusables, FocusableInfo{
			ID:       btn.ID,
			Y:        0,
			Height:   1,
			IsButton: true,
		})
		x += btnWidth + 1
	}

	return RenderedSection{
		Content:    lipgloss.JoinHorizontal(lipgloss.Top, rendered...),
		Height:     1,
		Focusables: focusables,
	}
}

func (b *buttonsSection) FocusableIDs() []string {
	ids := make([]string, len(b.buttons))
	for i, btn := range b.buttons {
		ids[i] = btn.ID
	}
	return ids
}

type inputSection struct {
	id    string
	label string
	model *textinput.Model
}

func Input(id string, model *textinput.Model, opts ...func(*inputSection)) Section {
	s := &inputSection{id: id, model: model}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

func InputWithLabel(id, label string, model *textinput.Model, opts ...func(*inputSection)) Section {
	s := &inputSection{id: id, label: label, model: model}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

func (i *inputSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	focused := focusID == i.id
	if focused {
		i.model.Focus()
	} else {
		i.model.Blur()
	}

	var lines []string
	if i.label != "" {
		lines = append(lines, styles.Muted.Render(i.label))
	}

	inputStyle := lipgloss.NewStyle().Width(contentWidth)
	lines = append(lines, inputStyle.Render(i.model.View()))

	return RenderedSection{
		Content:    strings.Join(lines, "\n"),
		Height:     len(lines),
		Focusables: []FocusableInfo{{ID: i.id, Y: 0, Height: len(lines)}},
	}
}

func (i *inputSection) FocusableIDs() []string {
	return []string{i.id}
}

func (i *inputSection) Update(msg tea.Msg, focusID string) (string, tea.Cmd) {
	if focusID != i.id {
		return "", nil
	}
	var cmd tea.Cmd
	*i.model, cmd = i.model.Update(msg)
	return "", cmd
}

type ListItem struct {
	ID    string
	Label string
}

type listSection struct {
	id           string
	items        []ListItem
	selectedIdx  *int
	maxVisible   int
	scrollOffset int
}

type ListOption func(*listSection)

func WithMaxVisible(n int) ListOption {
	return func(l *listSection) { l.maxVisible = n }
}

func List(id string, items []ListItem, selectedIdx *int, opts ...ListOption) Section {
	l := &listSection{id: id, items: items, selectedIdx: selectedIdx, maxVisible: 10}
	for _, opt := range opts {
		opt(l)
	}
	return l
}

func (l *listSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	var lines []string
	var focusables []FocusableInfo

	start := l.scrollOffset
	end := min(len(l.items), start+l.maxVisible)

	for i := start; i < end; i++ {
		item := l.items[i]
		isSelected := l.selectedIdx != nil && *l.selectedIdx == i
		isFocused := focusID == item.ID

		var style lipgloss.Style
		if isSelected || isFocused {
			style = styles.ListItemSelected
		} else {
			style = styles.ListItemNormal
		}

		label := ui.TruncateString(item.Label, contentWidth-3)
		line := style.Render(fmt.Sprintf("  %s", label))
		lines = append(lines, line)

		focusables = append(focusables, FocusableInfo{
			ID:     item.ID,
			Y:      i - start,
			Height: 1,
		})
	}

	if len(l.items) > l.maxVisible {
		total := len(l.items)
		hint := styles.Muted.Render(fmt.Sprintf("  (%d-%d of %d)", start+1, end, total))
		lines = append(lines, hint)
	}

	return RenderedSection{
		Content:    strings.Join(lines, "\n"),
		Height:     len(lines),
		Focusables: focusables,
	}
}

func (l *listSection) FocusableIDs() []string {
	ids := make([]string, len(l.items))
	for i, item := range l.items {
		ids[i] = item.ID
	}
	return ids
}

func (l *listSection) Update(msg tea.Msg, focusID string) (string, tea.Cmd) {
	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return "", nil
	}

	switch keyMsg.String() {
	case "up", "k":
		if l.selectedIdx != nil && *l.selectedIdx > 0 {
			*l.selectedIdx--
			if *l.selectedIdx < l.scrollOffset {
				l.scrollOffset = *l.selectedIdx
			}
		}
	case "down", "j":
		if l.selectedIdx != nil && *l.selectedIdx < len(l.items)-1 {
			*l.selectedIdx++
			if *l.selectedIdx >= l.scrollOffset+l.maxVisible {
				l.scrollOffset++
			}
		}
	case "enter":
		if l.selectedIdx != nil && *l.selectedIdx >= 0 && *l.selectedIdx < len(l.items) {
			return l.items[*l.selectedIdx].ID, nil
		}
	}
	return "", nil
}

type checkboxSection struct {
	id      string
	label   string
	checked *bool
}

func Checkbox(id, label string, checked *bool) Section {
	return &checkboxSection{id: id, label: label, checked: checked}
}

func (c *checkboxSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	focused := focusID == c.id
	var checkbox string
	if *c.checked {
		checkbox = "☑"
	} else {
		checkbox = "☐"
	}

	style := styles.ListItemNormal
	if focused {
		style = styles.ListItemSelected
	}

	line := style.Render(fmt.Sprintf("  %s %s", checkbox, c.label))
	return RenderedSection{
		Content:    line,
		Height:     1,
		Focusables: []FocusableInfo{{ID: c.id, Y: 0, Height: 1}},
	}
}

func (c *checkboxSection) FocusableIDs() []string {
	return []string{c.id}
}

func (c *checkboxSection) Update(msg tea.Msg, focusID string) (string, tea.Cmd) {
	if focusID != c.id {
		return "", nil
	}
	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return "", nil
	}
	if keyMsg.String() == "enter" || keyMsg.String() == " " {
		*c.checked = !*c.checked
	}
	return "", nil
}

type whenSection struct {
	condition func() bool
	inner     Section
}

func When(condition func() bool, section Section) Section {
	return &whenSection{condition: condition, inner: section}
}

func (w *whenSection) Render(contentWidth int, focusID, hoverID string) RenderedSection {
	if !w.condition() {
		return RenderedSection{}
	}
	return w.inner.Render(contentWidth, focusID, hoverID)
}

func (w *whenSection) FocusableIDs() []string {
	if !w.condition() {
		return nil
	}
	return w.inner.FocusableIDs()
}
