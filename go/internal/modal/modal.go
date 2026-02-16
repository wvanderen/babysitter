package modal

import (
	tea "github.com/charmbracelet/bubbletea"
)

type Variant int

const (
	VariantDefault Variant = iota
	VariantDanger
	VariantWarning
	VariantInfo
)

const (
	DefaultWidth  = 50
	MinModalWidth = 30
	MaxModalWidth = 100
	ModalPadding  = 6
)

type Option func(*Modal)

func WithWidth(w int) Option {
	return func(m *Modal) {
		m.width = w
	}
}

func WithVariant(v Variant) Option {
	return func(m *Modal) {
		m.variant = v
	}
}

func WithHints(show bool) Option {
	return func(m *Modal) {
		m.showHints = show
	}
}

func WithPrimaryAction(actionID string) Option {
	return func(m *Modal) {
		m.primaryAction = actionID
	}
}

func WithCloseOnBackdrop(close bool) Option {
	return func(m *Modal) {
		m.closeOnBackdrop = close
	}
}

type Modal struct {
	title           string
	variant         Variant
	width           int
	sections        []Section
	showHints       bool
	primaryAction   string
	closeOnBackdrop bool

	focusIdx     int
	focusIDs     []string
	scrollOffset int

	cachedWidth  int
	cachedRender string
}

func New(title string, opts ...Option) *Modal {
	m := &Modal{
		title:           title,
		variant:         VariantDefault,
		width:           DefaultWidth,
		showHints:       true,
		closeOnBackdrop: true,
	}
	for _, opt := range opts {
		opt(m)
	}
	return m
}

func (m *Modal) AddSection(s Section) *Modal {
	m.sections = append(m.sections, s)
	m.cachedRender = ""
	return m
}

func (m *Modal) Sections() []Section {
	return m.sections
}

func (m *Modal) SetWidth(w int) {
	if m.width != w {
		m.width = w
		m.cachedRender = ""
	}
}

func (m *Modal) Width() int {
	return m.width
}

func (m *Modal) currentFocusID() string {
	if m.focusIdx >= 0 && m.focusIdx < len(m.focusIDs) {
		return m.focusIDs[m.focusIdx]
	}
	return ""
}

func (m *Modal) cycleFocus(dir int) {
	if len(m.focusIDs) == 0 {
		return
	}
	m.focusIdx = (m.focusIdx + dir + len(m.focusIDs)) % len(m.focusIDs)
	m.ensureFocusVisible()
}

func (m *Modal) ensureFocusVisible() {
}

func (m *Modal) SetFocus(id string) {
	for i, fid := range m.focusIDs {
		if fid == id {
			m.focusIdx = i
			return
		}
	}
}

func (m *Modal) FocusedID() string {
	return m.currentFocusID()
}

func (m *Modal) Reset() {
	m.focusIdx = 0
	m.scrollOffset = 0
	m.cachedRender = ""
}

type HitRegion struct {
	ID   string
	X, Y int
	W, H int
}

type HitMap struct {
	regions []HitRegion
}

func (h *HitMap) Clear() {
	h.regions = nil
}

func (h *HitMap) AddRect(id string, x, y, w, hi int) {
	h.regions = append(h.regions, HitRegion{ID: id, X: x, Y: y, W: w, H: hi})
}

func (h *HitMap) Test(x, y int) *HitRegion {
	for i := len(h.regions) - 1; i >= 0; i-- {
		r := &h.regions[i]
		if x >= r.X && x < r.X+r.W && y >= r.Y && y < r.Y+r.H {
			return r
		}
	}
	return nil
}

type MouseAction int

const (
	ActionNone MouseAction = iota
	ActionClick
	ActionHover
	ActionScrollUp
	ActionScrollDown
)

type MouseMsg struct {
	Action MouseAction
	X, Y   int
	Region *HitRegion
}

func (m *Modal) HandleKey(msg tea.KeyMsg) (action string, cmd tea.Cmd) {
	key := msg.String()

	switch key {
	case "esc":
		return "cancel", nil

	case "tab":
		m.cycleFocus(1)
		return "", nil

	case "shift+tab":
		m.cycleFocus(-1)
		return "", nil

	case "enter":
		focusID := m.currentFocusID()
		if focusID != "" {
			for _, s := range m.sections {
				if us, ok := s.(interface {
					Update(tea.Msg, string) (string, tea.Cmd)
				}); ok {
					action, cmd = us.Update(msg, focusID)
					if action != "" {
						return action, cmd
					}
				}
			}
			if m.primaryAction != "" {
				return m.primaryAction, cmd
			}
			return focusID, cmd
		}
		return "", nil

	default:
		for _, s := range m.sections {
			if us, ok := s.(interface {
				Update(tea.Msg, string) (string, tea.Cmd)
			}); ok {
				action, cmd = us.Update(msg, m.currentFocusID())
				if action != "" {
					return action, cmd
				}
			}
		}
		return "", nil
	}
}

func (m *Modal) HandleMouse(msg MouseMsg) string {
	switch msg.Action {
	case ActionClick:
		if msg.Region == nil {
			return ""
		}
		id := msg.Region.ID

		if id == "modal-backdrop" {
			if m.closeOnBackdrop {
				return "cancel"
			}
			return ""
		}

		if id == "modal-body" {
			return ""
		}

		for i, fid := range m.focusIDs {
			if fid == id {
				m.focusIdx = i
				return id
			}
		}
		return ""

	case ActionScrollUp:
		if msg.Region != nil && msg.Region.ID == "modal-body" {
			m.scrollOffset = max(0, m.scrollOffset-1)
			m.cachedRender = ""
		}
		return ""

	case ActionScrollDown:
		if msg.Region != nil && msg.Region.ID == "modal-body" {
			m.scrollOffset++
			m.cachedRender = ""
		}
		return ""
	}

	return ""
}
