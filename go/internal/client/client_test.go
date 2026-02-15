package client

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNew(t *testing.T) {
	c := New("http://localhost:4001")
	if c.baseURL != "http://localhost:4001" {
		t.Errorf("expected baseURL to be http://localhost:4001, got %s", c.baseURL)
	}
	if c.httpClient == nil {
		t.Error("expected httpClient to be initialized")
	}
}

func TestNewWithOptions(t *testing.T) {
	customClient := &http.Client{}
	c := New("http://localhost:4001", WithHTTPClient(customClient))
	if c.httpClient != customClient {
		t.Error("expected custom httpClient to be set")
	}
}

func TestListSessions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/sessions" {
			t.Errorf("expected /api/sessions, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"sessions": []map[string]interface{}{
				{"id": "session-1", "status": "running"},
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	list, err := c.ListSessions()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(list.Sessions) != 1 {
		t.Errorf("expected 1 session, got %d", len(list.Sessions))
	}
	if list.Sessions[0].ID != "session-1" {
		t.Errorf("expected session-1, got %s", list.Sessions[0].ID)
	}
}

func TestGetSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/sessions/session-1" {
			t.Errorf("expected /api/sessions/session-1, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":     "session-1",
				"status": "running",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	sess, err := c.GetSession("session-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sess.ID != "session-1" {
		t.Errorf("expected session-1, got %s", sess.ID)
	}
}

func TestGetSessionNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "not found"})
	}))
	defer server.Close()

	c := New(server.URL)
	_, err := c.GetSession("nonexistent")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	apiErr, ok := err.(*APIError)
	if !ok {
		t.Fatalf("expected APIError, got %T", err)
	}
	if apiErr.StatusCode != http.StatusNotFound {
		t.Errorf("expected 404, got %d", apiErr.StatusCode)
	}
}

func TestCreateSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/api/sessions" {
			t.Errorf("expected /api/sessions, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":     "new-session",
				"status": "initializing",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	sess, err := c.CreateSession(map[string]interface{}{"id": "new-session"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sess.ID != "new-session" {
		t.Errorf("expected new-session, got %s", sess.ID)
	}
}

func TestDeleteSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "DELETE" {
			t.Errorf("expected DELETE, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
	}))
	defer server.Close()

	c := New(server.URL)
	if err := c.DeleteSession("session-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestPauseSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/sessions/session-1/pause" {
			t.Errorf("expected /api/sessions/session-1/pause, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":     "session-1",
				"status": "paused",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	if err := c.PauseSession("session-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestResumeSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/sessions/session-1/resume" {
			t.Errorf("expected /api/sessions/session-1/resume, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":     "session-1",
				"status": "running",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	if err := c.ResumeSession("session-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestListWorkflows(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/workflows" {
			t.Errorf("expected /api/workflows, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"workflows": []map[string]interface{}{
				{"id": "workflow-1", "name": "Test Workflow"},
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	list, err := c.ListWorkflows()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(list.Workflows) != 1 {
		t.Errorf("expected 1 workflow, got %d", len(list.Workflows))
	}
}

func TestExecuteWorkflow(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/workflows/workflow-1/execute" {
			t.Errorf("expected /api/workflows/workflow-1/execute, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	c := New(server.URL)
	if err := c.ExecuteWorkflow("workflow-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "internal error"})
	}))
	defer server.Close()

	c := New(server.URL)
	_, err := c.ListSessions()
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	apiErr, ok := err.(*APIError)
	if !ok {
		t.Fatalf("expected APIError, got %T", err)
	}
	if apiErr.StatusCode != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", apiErr.StatusCode)
	}
	if apiErr.Error() == "" {
		t.Error("expected error message")
	}
}

func TestWSMessageFields(t *testing.T) {
	msg := WSMessage{
		Event:     "session:output",
		SessionID: "session-1",
		Stage:     "stage-1",
		Output:    "Hello world",
		Status:    "running",
		Data:      map[string]interface{}{"key": "value"},
	}

	if msg.Event != "session:output" {
		t.Errorf("expected session:output, got %s", msg.Event)
	}
	if msg.Output != "Hello world" {
		t.Errorf("expected Hello world, got %s", msg.Output)
	}
}

func TestInterveneSession(t *testing.T) {
	tests := []struct {
		name   string
		action InterventionAction
	}{
		{"retry", InterventionRetry},
		{"restart", InterventionRestart},
		{"escalate", InterventionEscalate},
		{"skip", InterventionSkip},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/sessions/session-1/intervene" {
					t.Errorf("expected /api/sessions/session-1/intervene, got %s", r.URL.Path)
				}
				if r.Method != "POST" {
					t.Errorf("expected POST, got %s", r.Method)
				}
				w.WriteHeader(http.StatusOK)
				json.NewEncoder(w).Encode(map[string]interface{}{
					"status": "ok",
					"action": tt.name,
				})
			}))
			defer server.Close()

			c := New(server.URL)
			if err := c.InterveneSession("session-1", tt.action, "test reason"); err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestAttachSession(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/sessions/session-1" {
			t.Errorf("expected /api/sessions/session-1, got %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":        "session-1",
				"tmux_name": "babysitter-session-1",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	tmuxSession, err := c.AttachSession("session-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tmuxSession != "babysitter-session-1" {
		t.Errorf("expected babysitter-session-1, got %s", tmuxSession)
	}
}

func TestAttachSessionNoTmux(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"session": map[string]interface{}{
				"id":        "session-1",
				"tmux_name": "",
			},
		})
	}))
	defer server.Close()

	c := New(server.URL)
	tmuxSession, err := c.AttachSession("session-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tmuxSession != "" {
		t.Errorf("expected empty tmux session, got %s", tmuxSession)
	}
}
