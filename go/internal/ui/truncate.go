package ui

import (
	"strings"

	"github.com/mattn/go-runewidth"
)

func TruncateString(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}

	runes := []rune(s)
	width := runewidth.StringWidth(s)
	if width <= maxLen {
		return s
	}

	var result []rune
	currentWidth := 0

	for _, r := range runes {
		rw := runewidth.RuneWidth(r)
		if currentWidth+rw > maxLen-3 {
			break
		}
		result = append(result, r)
		currentWidth += rw
	}

	return string(result) + "..."
}

func TruncateMid(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}

	width := runewidth.StringWidth(s)
	if width <= maxLen {
		return s
	}

	if maxLen <= 3 {
		return "..."
	}

	halfLen := (maxLen - 3) / 2
	left := truncateRunesToWidth([]rune(s), halfLen)
	right := truncateRunesFromEnd([]rune(s), halfLen)

	return string(left) + "..." + string(right)
}

func TruncateStart(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}

	width := runewidth.StringWidth(s)
	if width <= maxLen {
		return s
	}

	if maxLen <= 3 {
		return "..."
	}

	runes := truncateRunesFromEnd([]rune(s), maxLen-3)
	return "..." + string(runes)
}

func truncateRunesToWidth(runes []rune, maxWidth int) []rune {
	var result []rune
	currentWidth := 0

	for _, r := range runes {
		rw := runewidth.RuneWidth(r)
		if currentWidth+rw > maxWidth {
			break
		}
		result = append(result, r)
		currentWidth += rw
	}

	return result
}

func truncateRunesFromEnd(runes []rune, maxWidth int) []rune {
	var result []rune
	currentWidth := 0

	for i := len(runes) - 1; i >= 0; i-- {
		rw := runewidth.RuneWidth(runes[i])
		if currentWidth+rw > maxWidth {
			break
		}
		result = append([]rune{runes[i]}, result...)
		currentWidth += rw
	}

	return result
}

func PadRight(s string, width int) string {
	currentWidth := runewidth.StringWidth(s)
	if currentWidth >= width {
		return s
	}
	return s + strings.Repeat(" ", width-currentWidth)
}

func PadLeft(s string, width int) string {
	currentWidth := runewidth.StringWidth(s)
	if currentWidth >= width {
		return s
	}
	return strings.Repeat(" ", width-currentWidth) + s
}
