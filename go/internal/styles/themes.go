package styles

import "github.com/charmbracelet/lipgloss"

type Theme struct {
	Name          string
	Primary       lipgloss.Color
	Secondary     lipgloss.Color
	Accent        lipgloss.Color
	Success       lipgloss.Color
	Warning       lipgloss.Color
	Error         lipgloss.Color
	Info          lipgloss.Color
	TextPrimary   lipgloss.Color
	TextSecondary lipgloss.Color
	TextMuted     lipgloss.Color
	BgPrimary     lipgloss.Color
	BgSecondary   lipgloss.Color
	BgTertiary    lipgloss.Color
	BorderActive  lipgloss.Color
	BorderNormal  lipgloss.Color
}

var DefaultTheme = Theme{
	Name:          "default",
	Primary:       Primary,
	Secondary:     Secondary,
	Accent:        Accent,
	Success:       Success,
	Warning:       Warning,
	Error:         Error,
	Info:          Info,
	TextPrimary:   TextPrimary,
	TextSecondary: TextSecondary,
	TextMuted:     TextMuted,
	BgPrimary:     BgPrimary,
	BgSecondary:   BgSecondary,
	BgTertiary:    BgTertiary,
	BorderActive:  BorderActive,
	BorderNormal:  BorderNormal,
}

var CurrentTheme = DefaultTheme

func SetTheme(theme Theme) {
	CurrentTheme = theme
	Primary = theme.Primary
	Secondary = theme.Secondary
	Accent = theme.Accent
	Success = theme.Success
	Warning = theme.Warning
	Error = theme.Error
	Info = theme.Info
	TextPrimary = theme.TextPrimary
	TextSecondary = theme.TextSecondary
	TextMuted = theme.TextMuted
	BgPrimary = theme.BgPrimary
	BgSecondary = theme.BgSecondary
	BgTertiary = theme.BgTertiary
	BorderActive = theme.BorderActive
	BorderNormal = theme.BorderNormal
}
