package tui

type Session struct {
	ID       string
	IssueID  string
	Stage    string
	Status   string
	Duration string
	Output   []string
}

type Styles struct {
	Active    string
	Idle      string
	Completed string
	Failed    string
}

func DefaultStyles() Styles {
	return Styles{
		Active:    "●",
		Idle:      "○",
		Completed: "✓",
		Failed:    "✗",
	}
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
	return s.ID + "  " + s.IssueID + "  [" + s.Stage + "]  " + s.Status
}
