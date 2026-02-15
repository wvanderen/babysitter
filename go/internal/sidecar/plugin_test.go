package sidecar

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/marcus/babysitter/go/internal/tui"
	"github.com/marcus/babysitter/go/pkg/plugin"
)

func TestNew(t *testing.T) {
	p := New()
	if p == nil {
		t.Fatal("New() returned nil")
	}

	info := p.Info()
	if info.ID != "babysitter" {
		t.Errorf("expected ID 'babysitter', got %q", info.ID)
	}
	if info.Name != "Babysitter" {
		t.Errorf("expected Name 'Babysitter', got %q", info.Name)
	}
	if info.Version != "0.1.0" {
		t.Errorf("expected Version '0.1.0', got %q", info.Version)
	}
}

func TestInit(t *testing.T) {
	p := New()
	ctx := &plugin.Context{Config: map[string]interface{}{}}

	err := p.Init(ctx)
	if err != nil {
		t.Fatalf("Init() returned error: %v", err)
	}

	if p.client == nil {
		t.Error("client not initialized")
	}
}

func TestInitWithCustomURL(t *testing.T) {
	p := New()
	ctx := &plugin.Context{
		Config: map[string]interface{}{
			"daemon_url": "http://custom:8080",
		},
	}

	err := p.Init(ctx)
	if err != nil {
		t.Fatalf("Init() returned error: %v", err)
	}
}

func TestCommands(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	commands := p.Commands()
	if len(commands) == 0 {
		t.Fatal("no commands registered")
	}

	expectedCommands := []string{
		"babysitter.pause",
		"babysitter.resume",
		"babysitter.escalate",
		"babysitter.skip",
		"babysitter.attach",
		"babysitter.refresh",
		"babysitter.focus.sessions",
		"babysitter.focus.output",
		"babysitter.focus.controls",
	}

	commandMap := make(map[string]bool)
	for _, cmd := range commands {
		commandMap[cmd.ID] = true
	}

	for _, expected := range expectedCommands {
		if !commandMap[expected] {
			t.Errorf("missing command %q", expected)
		}
	}
}

func TestUpdate(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	updated, cmd := p.Update(tea.WindowSizeMsg{Width: 100, Height: 50})
	if cmd != nil {
		t.Error("expected nil cmd for WindowSizeMsg")
	}

	updatedPlugin, ok := updated.(plugin.Plugin)
	if !ok {
		t.Fatal("Update did not return plugin.Plugin")
	}

	bp, ok := updatedPlugin.(*BabysitterPlugin)
	if !ok {
		t.Fatal("Update did not return *BabysitterPlugin")
	}

	if bp.appModel.View() == "" {
		t.Error("View should not be empty")
	}
}

func TestView(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	view := p.View()
	if view == "" {
		t.Error("View() returned empty string")
	}
}

func TestUpdateQuit(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	_, _ = p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})

	if !p.IsQuitting() {
		t.Error("expected IsQuitting() to be true after 'q' key")
	}
}

func TestFocusCommand(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	commands := p.Commands()
	var focusOutputCmd plugin.Command
	for _, cmd := range commands {
		if cmd.ID == "babysitter.focus.output" {
			focusOutputCmd = cmd
			break
		}
	}

	if focusOutputCmd.ID == "" {
		t.Fatal("focus.output command not found")
	}

	teaCmd := focusOutputCmd.Handler()
	if teaCmd == nil {
		t.Fatal("Handler returned nil")
	}

	msg := teaCmd()
	focusMsg, ok := msg.(tui.FocusMsg)
	if !ok {
		t.Fatalf("expected tui.FocusMsg, got %T", msg)
	}
	if focusMsg.Area != tui.FocusOutput {
		t.Errorf("expected FocusOutput, got %v", focusMsg.Area)
	}
}

func TestControlCommands(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	tests := []struct {
		cmdID      string
		wantAction tui.ControlAction
	}{
		{"babysitter.pause", tui.ActionPause},
		{"babysitter.resume", tui.ActionResume},
		{"babysitter.escalate", tui.ActionEscalate},
		{"babysitter.skip", tui.ActionSkip},
		{"babysitter.attach", tui.ActionAttach},
		{"babysitter.refresh", tui.ActionRefresh},
	}

	commands := p.Commands()
	cmdMap := make(map[string]plugin.Command)
	for _, cmd := range commands {
		cmdMap[cmd.ID] = cmd
	}

	for _, tt := range tests {
		t.Run(tt.cmdID, func(t *testing.T) {
			cmd, ok := cmdMap[tt.cmdID]
			if !ok {
				t.Fatalf("command %q not found", tt.cmdID)
			}

			teaCmd := cmd.Handler()
			if teaCmd == nil {
				t.Fatal("Handler returned nil")
			}

			msg := teaCmd()
			controlMsg, ok := msg.(tui.ControlMsg)
			if !ok {
				t.Fatalf("expected tui.ControlMsg, got %T", msg)
			}
			if controlMsg.Action != tt.wantAction {
				t.Errorf("expected action %v, got %v", tt.wantAction, controlMsg.Action)
			}
		})
	}
}

func TestAppModel(t *testing.T) {
	p := New()
	_ = p.Init(&plugin.Context{Config: map[string]interface{}{}})

	am := p.AppModel()
	if am == nil {
		t.Fatal("AppModel() returned nil")
	}
}
