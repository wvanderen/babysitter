package tui

import (
	"testing"

	"github.com/charmbracelet/lipgloss"
)

func TestFormatStatus(t *testing.T) {
	tests := []struct {
		status   string
		contains string
	}{
		{"running", "●"},
		{"active", "●"},
		{"idle", "○"},
		{"pending", "○"},
		{"completed", "✓"},
		{"success", "✓"},
		{"failed", "✗"},
		{"error", "✗"},
		{"unknown", "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.status, func(t *testing.T) {
			result := FormatStatus(tt.status)
			if lipgloss.Width(result) == 0 {
				t.Errorf("FormatStatus(%q) returned empty result", tt.status)
			}
		})
	}
}

func TestSessionItemFilterValue(t *testing.T) {
	s := SessionItem{
		ID:      "sess-123",
		IssueID: "td-456",
		Stage:   "build",
		Status:  "running",
	}

	filterVal := s.FilterValue()
	if filterVal != "sess-123 td-456" {
		t.Errorf("FilterValue() = %q, want %q", filterVal, "sess-123 td-456")
	}
}

func TestNewSessionList(t *testing.T) {
	sl := NewSessionList()

	if sl.list.Title != "Sessions" {
		t.Errorf("Expected title 'Sessions', got %q", sl.list.Title)
	}

	if !sl.focused {
		t.Error("Expected session list to be focused initially")
	}

	if sl.list.FilteringEnabled() != true {
		t.Error("Expected filtering to be enabled")
	}
}

func TestSessionListSetFocused(t *testing.T) {
	sl := NewSessionList()
	sl.SetFocused(false)

	if sl.focused {
		t.Error("Expected focused to be false")
	}

	sl.SetFocused(true)
	if !sl.focused {
		t.Error("Expected focused to be true")
	}
}

func TestNewOutputViewer(t *testing.T) {
	ov := NewOutputViewer()

	if ov.title != "Output" {
		t.Errorf("Expected title 'Output', got %q", ov.title)
	}

	if len(ov.output) != 0 {
		t.Error("Expected output to be empty initially")
	}
}

func TestOutputViewerAppendOutput(t *testing.T) {
	ov := NewOutputViewer()

	ov.AppendOutput("line1\nline2")

	if len(ov.output) != 2 {
		t.Errorf("Expected 2 lines, got %d", len(ov.output))
	}

	if ov.output[0] != "line1" || ov.output[1] != "line2" {
		t.Errorf("Unexpected output content: %v", ov.output)
	}
}

func TestOutputViewerSetOutput(t *testing.T) {
	ov := NewOutputViewer()

	ov.SetOutput([]string{"a", "b", "c"})

	if len(ov.output) != 3 {
		t.Errorf("Expected 3 lines, got %d", len(ov.output))
	}
}

func TestOutputViewerClear(t *testing.T) {
	ov := NewOutputViewer()
	ov.AppendOutput("some output")
	ov.Clear()

	if len(ov.output) != 0 {
		t.Error("Expected output to be cleared")
	}
}

func TestNewControls(t *testing.T) {
	c := NewControls()

	if len(c.buttons) != 6 {
		t.Errorf("Expected 6 buttons, got %d", len(c.buttons))
	}

	if c.selected != 0 {
		t.Errorf("Expected selected to be 0, got %d", c.selected)
	}
}

func TestControlsSetSession(t *testing.T) {
	c := NewControls()

	session := &SessionItem{
		ID:      "sess-789",
		IssueID: "td-999",
		Status:  "running",
	}

	c.SetSession(session)

	if c.session == nil {
		t.Fatal("Expected session to be set")
	}

	if c.session.ID != "sess-789" {
		t.Errorf("Expected session ID 'sess-789', got %q", c.session.ID)
	}
}

func TestControlsButtonNavigation(t *testing.T) {
	c := NewControls()

	c.NextButton()
	if c.selected != 1 {
		t.Errorf("Expected selected to be 1, got %d", c.selected)
	}

	for i := 0; i < 5; i++ {
		c.NextButton()
	}
	if c.selected != 0 {
		t.Errorf("Expected selected to wrap to 0, got %d", c.selected)
	}

	c.PrevButton()
	if c.selected != 5 {
		t.Errorf("Expected selected to wrap to 5, got %d", c.selected)
	}
}

func TestDefaultStyles(t *testing.T) {
	styles := DefaultStyles()

	if styles.Active == "" {
		t.Error("Expected Active style to be set")
	}
	if styles.Idle == "" {
		t.Error("Expected Idle style to be set")
	}
	if styles.Completed == "" {
		t.Error("Expected Completed style to be set")
	}
	if styles.Failed == "" {
		t.Error("Expected Failed style to be set")
	}
}

func TestFormatSession(t *testing.T) {
	s := Session{
		ID:       "sess-1",
		IssueID:  "td-1",
		Stage:    "build",
		Status:   "running",
		Duration: "5s",
	}

	result := FormatSession(s)

	if result == "" {
		t.Error("Expected non-empty result")
	}
}

func TestFormatSessionList(t *testing.T) {
	t.Run("empty list", func(t *testing.T) {
		result := FormatSessionList([]Session{})
		if result != "No active sessions" {
			t.Errorf("Expected 'No active sessions', got %q", result)
		}
	})

	t.Run("with sessions", func(t *testing.T) {
		sessions := []Session{
			{ID: "1", IssueID: "td-1", Stage: "build", Status: "running"},
			{ID: "2", IssueID: "td-2", Stage: "test", Status: "idle"},
		}
		result := FormatSessionList(sessions)
		if result == "" {
			t.Error("Expected non-empty result")
		}
	})
}

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		ms       int64
		expected string
	}{
		{100, "100ms"},
		{1500, "1s"},
		{65000, "1m5s"},
		{125000, "2m5s"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			result := FormatDuration(tt.ms)
			if result != tt.expected {
				t.Errorf("FormatDuration(%d) = %q, want %q", tt.ms, result, tt.expected)
			}
		})
	}
}
