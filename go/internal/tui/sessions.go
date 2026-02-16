package tui

import "fmt"

type Session struct {
	ID       string
	IssueID  string
	Stage    string
	Status   string
	Duration string
	Output   []string
}

func FormatSessionList(sessions []Session) string {
	if len(sessions) == 0 {
		return "No active sessions"
	}

	result := ""
	for _, s := range sessions {
		result += FormatSession(s) + "\n"
	}
	return result
}

func FormatSession(s Session) string {
	return s.ID + "  " + s.IssueID + "  [" + s.Stage + "]  " + FormatStatus(s.Status)
}

func FormatDuration(ms int64) string {
	if ms < 1000 {
		return fmt.Sprintf("%dms", ms)
	}
	seconds := ms / 1000
	if seconds < 60 {
		return fmt.Sprintf("%ds", seconds)
	}
	minutes := seconds / 60
	remainingSeconds := seconds % 60
	return fmt.Sprintf("%dm%ds", minutes, remainingSeconds)
}
