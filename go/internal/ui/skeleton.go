package ui

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/wvanderen/babysitter/go/internal/styles"
)

var (
	skeletonMu      sync.Mutex
	skeletonFrame   int
	skeletonStarted bool
)

func StartSkeletonAnimation() {
	skeletonMu.Lock()
	defer skeletonMu.Unlock()

	if skeletonStarted {
		return
	}
	skeletonStarted = true

	go func() {
		ticker := time.NewTicker(120 * time.Millisecond)
		defer ticker.Stop()

		for range ticker.C {
			skeletonMu.Lock()
			skeletonFrame = (skeletonFrame + 1) % 3
			skeletonMu.Unlock()
		}
	}()
}

type Skeleton struct {
	Width  int
	Height int
}

func NewSkeleton(width, height int) Skeleton {
	StartSkeletonAnimation()
	return Skeleton{Width: width, Height: height}
}

func (s Skeleton) View() string {
	skeletonMu.Lock()
	frame := skeletonFrame
	skeletonMu.Unlock()

	shimmerColors := []lipgloss.Color{
		lipgloss.Color("#2D3748"),
		lipgloss.Color("#3D4A5C"),
		lipgloss.Color("#4A5568"),
	}

	color := shimmerColors[frame]

	style := lipgloss.NewStyle().
		Background(color).
		Width(s.Width).
		Height(1)

	var lines []string
	for i := 0; i < s.Height; i++ {
		lines = append(lines, style.Render(""))
	}

	return strings.Join(lines, "\n")
}

func (s Skeleton) Row(width int) string {
	skeletonMu.Lock()
	frame := skeletonFrame
	skeletonMu.Unlock()

	shimmerColors := []lipgloss.Color{
		lipgloss.Color("#2D3748"),
		lipgloss.Color("#3D4A5C"),
		lipgloss.Color("#4A5568"),
	}

	color := shimmerColors[frame]

	style := lipgloss.NewStyle().
		Background(color).
		Width(width).
		Height(1)

	return style.Render("")
}

func SkeletonText(width int) string {
	skeletonMu.Lock()
	frame := skeletonFrame
	skeletonMu.Unlock()

	shimmerColors := []lipgloss.Color{
		lipgloss.Color("#2D3748"),
		lipgloss.Color("#3D4A5C"),
		lipgloss.Color("#4A5568"),
	}

	color := shimmerColors[frame]

	style := lipgloss.NewStyle().
		Background(color).
		Width(width).
		Height(1)

	return style.Render("")
}

func SkeletonList(count, width int) string {
	var lines []string
	for i := 0; i < count; i++ {
		itemWidth := width - (i % 3 * 5)
		if itemWidth < 10 {
			itemWidth = width - 10
		}
		lines = append(lines, SkeletonText(itemWidth))
		if i < count-1 {
			lines = append(lines, "")
		}
	}
	return strings.Join(lines, "\n")
}

func LoadingText(text string, width int) string {
	style := lipgloss.NewStyle().
		Foreground(styles.TextMuted).
		Width(width)

	return style.Render(text)
}

func LoadingSpinner() string {
	skeletonMu.Lock()
	frame := skeletonFrame
	skeletonMu.Unlock()

	spinners := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	return spinners[frame%len(spinners)]
}

func LoadingWithSpinner(text string) string {
	spinner := LoadingSpinner()
	style := lipgloss.NewStyle().Foreground(styles.TextSecondary)
	return fmt.Sprintf("%s %s", style.Render(spinner), text)
}
