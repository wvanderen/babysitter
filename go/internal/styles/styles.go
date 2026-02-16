package styles

import "github.com/charmbracelet/lipgloss"

var (
	PanelActive = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(BorderActive).
			Padding(0, 1)

	PanelInactive = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(BorderNormal).
			Padding(0, 1)

	PanelHeader = lipgloss.NewStyle().
			Background(Primary).
			Foreground(TextInverse).
			Padding(0, 1)

	PanelNoBorder = lipgloss.NewStyle().Padding(0, 1)

	Title = lipgloss.NewStyle().
		Bold(true).
		Foreground(TextPrimary)

	Subtitle = lipgloss.NewStyle().
			Foreground(TextHighlight)

	Body = lipgloss.NewStyle().
		Foreground(TextPrimary)

	Muted = lipgloss.NewStyle().
		Foreground(TextMuted)

	Subtle = lipgloss.NewStyle().
		Foreground(TextSubtle)

	Code = lipgloss.NewStyle().
		Foreground(Accent)

	Link = lipgloss.NewStyle().
		Foreground(LinkColor).
		Underline(true)

	KeyHint = lipgloss.NewStyle().
		Foreground(TextSecondary)

	Logo = lipgloss.NewStyle().
		Bold(true).
		Foreground(Primary)

	StatusRunning = lipgloss.NewStyle().
			Foreground(Info).
			Bold(true)

	StatusCompleted = lipgloss.NewStyle().
			Foreground(Success)

	StatusFailed = lipgloss.NewStyle().
			Foreground(Error)

	StatusPending = lipgloss.NewStyle().
			Foreground(TextMuted)

	StatusSkipped = lipgloss.NewStyle().
			Foreground(Warning)

	ListItemNormal = lipgloss.NewStyle().
			Foreground(TextPrimary)

	ListItemSelected = lipgloss.NewStyle().
				Foreground(TextSelectionColor).
				Background(BgTertiary)

	ListItemFocused = lipgloss.NewStyle().
			Foreground(TextPrimary).
			Background(Primary)

	ListCursor = lipgloss.NewStyle().
			Foreground(Primary).
			Bold(true)

	BarTitle = lipgloss.NewStyle().
			Foreground(TextPrimary).
			Bold(true)

	BarText = lipgloss.NewStyle().
		Foreground(TextSecondary)

	BarChip = lipgloss.NewStyle().
		Foreground(TextPrimary).
		Background(BgTertiary).
		Padding(0, 1)

	BarChipActive = lipgloss.NewStyle().
			Foreground(TextInverse).
			Background(Primary).
			Padding(0, 1)

	Footer = lipgloss.NewStyle().
		Foreground(TextSecondary).
		Background(BgSecondary).
		Padding(0, 1)

	Header = lipgloss.NewStyle().
		Foreground(TextPrimary).
		Background(BgSecondary).
		Padding(0, 1).
		Bold(true)

	ModalOverlay = lipgloss.NewStyle().
			Background(BgOverlay)

	ModalBox = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(Primary).
			Background(BgSecondary).
			Padding(1, 2)

	ModalTitle = lipgloss.NewStyle().
			Foreground(TextPrimary).
			Bold(true).
			Padding(0, 1)

	Button = lipgloss.NewStyle().
		Foreground(TextSecondary).
		Background(BgTertiary).
		Padding(0, 2)

	ButtonFocused = lipgloss.NewStyle().
			Foreground(TextPrimary).
			Background(Primary).
			Padding(0, 2).
			Bold(true)

	ButtonHover = lipgloss.NewStyle().
			Foreground(TextPrimary).
			Background(ButtonHoverColor).
			Padding(0, 2)

	ButtonDanger = lipgloss.NewStyle().
			Foreground(DangerLight).
			Background(DangerDark).
			Padding(0, 2)

	ButtonDangerFocused = lipgloss.NewStyle().
				Foreground(TextInverse).
				Background(DangerBright).
				Padding(0, 2).
				Bold(true)

	ButtonDangerHover = lipgloss.NewStyle().
				Foreground(TextInverse).
				Background(DangerHover).
				Padding(0, 2)

	TextSelection = lipgloss.NewStyle().
			Background(BgTertiary)

	PaletteEntry = lipgloss.NewStyle().
			Padding(0, 2)

	PaletteEntrySelected = lipgloss.NewStyle().
				Foreground(TextSelectionColor).
				Background(Primary).
				Padding(0, 2)

	PaletteKey = lipgloss.NewStyle().
			Foreground(TextMuted).
			Padding(0, 1)

	DiffAdd = lipgloss.NewStyle().
		Foreground(DiffAddFg).
		Background(DiffAddBg)

	DiffRemove = lipgloss.NewStyle().
			Foreground(DiffRemoveFg).
			Background(DiffRemoveBg)

	DiffContext = lipgloss.NewStyle().
			Foreground(TextMuted)

	DiffHeader = lipgloss.NewStyle().
			Foreground(TextSecondary).
			Bold(true)

	SearchMatch = lipgloss.NewStyle().
			Background(Secondary)

	SearchMatchCurrent = lipgloss.NewStyle().
				Background(Primary).
				Foreground(TextInverse)

	FuzzyMatchChar = lipgloss.NewStyle().
			Foreground(Primary).
			Bold(true)
)

func ResolveButtonStyle(focused, hover bool, danger bool) lipgloss.Style {
	if danger {
		if hover {
			return ButtonDangerHover
		}
		if focused {
			return ButtonDangerFocused
		}
		return ButtonDanger
	}
	if hover {
		return ButtonHover
	}
	if focused {
		return ButtonFocused
	}
	return Button
}
