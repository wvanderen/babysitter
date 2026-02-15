package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
	wsConn     *websocket.Conn
}

type ClientOption func(*Client)

func WithHTTPClient(httpClient *http.Client) ClientOption {
	return func(c *Client) {
		c.httpClient = httpClient
	}
}

func New(baseURL string, opts ...ClientOption) *Client {
	c := &Client{
		baseURL:    baseURL,
		httpClient: &http.Client{},
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

type Session struct {
	ID                string                 `json:"id"`
	Status            string                 `json:"status"`
	TmuxName          string                 `json:"tmux_name"`
	StartedAt         string                 `json:"started_at"`
	Metadata          map[string]interface{} `json:"metadata"`
	FailureReason     *string                `json:"failure_reason"`
	EscalationReason  *string                `json:"escalation_reason"`
	ValidationResults map[string]interface{} `json:"validation_results"`
}

type SessionList struct {
	Sessions []Session `json:"sessions"`
}

type Workflow struct {
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	Stages    map[string]Stage `json:"stages"`
	Status    string           `json:"status"`
	CreatedAt string           `json:"created_at"`
}

type Stage struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"`
	Config    map[string]interface{} `json:"config"`
	OnSuccess string                 `json:"on_success,omitempty"`
	OnFailure string                 `json:"on_failure,omitempty"`
	OnTimeout string                 `json:"on_timeout,omitempty"`
}

type WorkflowList struct {
	Workflows []Workflow `json:"workflows"`
}

type APIError struct {
	StatusCode int
	Message    string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("API error %d: %s", e.StatusCode, e.Message)
}

func (c *Client) doRequest(method, path string, body interface{}, result interface{}) error {
	var reqBody io.Reader
	if body != nil {
		jsonBody, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("failed to marshal request: %w", err)
		}
		reqBody = bytes.NewReader(jsonBody)
	}

	req, err := http.NewRequest(method, c.baseURL+path, reqBody)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return &APIError{
			StatusCode: resp.StatusCode,
			Message:    string(respBody),
		}
	}

	if result != nil {
		if err := json.NewDecoder(resp.Body).Decode(result); err != nil {
			return fmt.Errorf("failed to decode response: %w", err)
		}
	}

	return nil
}

func (c *Client) ListSessions() (*SessionList, error) {
	var list SessionList
	if err := c.doRequest("GET", "/api/sessions", nil, &list); err != nil {
		return nil, err
	}
	return &list, nil
}

func (c *Client) GetSession(id string) (*Session, error) {
	var result struct {
		Session Session `json:"session"`
	}
	if err := c.doRequest("GET", "/api/sessions/"+id, nil, &result); err != nil {
		return nil, err
	}
	return &result.Session, nil
}

func (c *Client) CreateSession(opts map[string]interface{}) (*Session, error) {
	body := map[string]interface{}{"session": opts}
	var result struct {
		Session Session `json:"session"`
	}
	if err := c.doRequest("POST", "/api/sessions", body, &result); err != nil {
		return nil, err
	}
	return &result.Session, nil
}

func (c *Client) DeleteSession(id string) error {
	return c.doRequest("DELETE", "/api/sessions/"+id, nil, nil)
}

func (c *Client) PauseSession(id string) error {
	return c.doRequest("POST", "/api/sessions/"+id+"/pause", nil, nil)
}

func (c *Client) ResumeSession(id string) error {
	return c.doRequest("POST", "/api/sessions/"+id+"/resume", nil, nil)
}

type InterventionAction string

const (
	InterventionRetry    InterventionAction = "retry"
	InterventionRestart  InterventionAction = "restart"
	InterventionEscalate InterventionAction = "escalate"
	InterventionSkip     InterventionAction = "skip"
)

func (c *Client) InterveneSession(id string, action InterventionAction, reason string) error {
	body := map[string]interface{}{
		"action": string(action),
	}
	if reason != "" {
		body["reason"] = reason
	}
	return c.doRequest("POST", "/api/sessions/"+id+"/intervene", body, nil)
}

func (c *Client) AttachSession(id string) (string, error) {
	session, err := c.GetSession(id)
	if err != nil {
		return "", err
	}
	return session.TmuxName, nil
}

func (c *Client) ListWorkflows() (*WorkflowList, error) {
	var list WorkflowList
	if err := c.doRequest("GET", "/api/workflows", nil, &list); err != nil {
		return nil, err
	}
	return &list, nil
}

func (c *Client) GetWorkflow(id string) (*Workflow, error) {
	var result struct {
		Workflow Workflow `json:"workflow"`
	}
	if err := c.doRequest("GET", "/api/workflows/"+id, nil, &result); err != nil {
		return nil, err
	}
	return &result.Workflow, nil
}

func (c *Client) CreateWorkflow(name string, stages []Stage) (*Workflow, error) {
	body := map[string]interface{}{
		"workflow": map[string]interface{}{
			"name":   name,
			"stages": stages,
		},
	}
	var result struct {
		Workflow Workflow `json:"workflow"`
	}
	if err := c.doRequest("POST", "/api/workflows", body, &result); err != nil {
		return nil, err
	}
	return &result.Workflow, nil
}

type WorkflowExecution struct {
	InstanceID string `json:"instance_id"`
	SessionID  string `json:"session_id"`
	WorkflowID string `json:"workflow_id"`
	Status     string `json:"status"`
}

func (c *Client) ExecuteWorkflow(workflowID string) error {
	return c.doRequest("POST", "/api/workflows/"+workflowID+"/execute", nil, nil)
}

func (c *Client) ExecuteWorkflowWithParams(workflowID, issueID string, variables map[string]interface{}) (*WorkflowExecution, error) {
	body := map[string]interface{}{}
	if issueID != "" {
		body["issue_id"] = issueID
	}
	if len(variables) > 0 {
		body["variables"] = variables
	}
	var result WorkflowExecution
	if err := c.doRequest("POST", "/api/workflows/"+workflowID+"/execute", body, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

type WSMessage struct {
	Event     string                 `json:"event"`
	SessionID string                 `json:"session_id,omitempty"`
	Session   *Session               `json:"session,omitempty"`
	Stage     string                 `json:"stage,omitempty"`
	Output    string                 `json:"output,omitempty"`
	Status    string                 `json:"status,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

type WSClient struct {
	conn      *websocket.Conn
	client    *Client
	onMessage func(WSMessage)
	done      chan struct{}
}

func (c *Client) ConnectWebSocket(onMessage func(WSMessage)) error {
	wsURL := "ws" + c.baseURL[4:] + "/ws"

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return fmt.Errorf("failed to connect websocket: %w", err)
	}

	wsClient := &WSClient{
		conn:      conn,
		client:    c,
		onMessage: onMessage,
		done:      make(chan struct{}),
	}
	c.wsConn = conn

	go wsClient.readLoop()

	return nil
}

func (c *Client) WebSocket() (*WSClient, error) {
	wsURL := "ws" + c.baseURL[4:] + "/ws"

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to connect websocket: %w", err)
	}
	c.wsConn = conn

	return &WSClient{
		conn:   conn,
		client: c,
		done:   make(chan struct{}),
	}, nil
}

func (ws *WSClient) readLoop() {
	defer ws.conn.Close()
	for {
		select {
		case <-ws.done:
			return
		default:
			var msg WSMessage
			if err := ws.conn.ReadJSON(&msg); err != nil {
				return
			}
			if ws.onMessage != nil {
				ws.onMessage(msg)
			}
		}
	}
}

func (ws *WSClient) OnMessage(handler func(WSMessage)) {
	ws.onMessage = handler
}

func (ws *WSClient) JoinSession(sessionID string) error {
	joinMsg := map[string]interface{}{
		"topic":   "session:" + sessionID,
		"event":   "phx_join",
		"payload": map[string]interface{}{},
		"ref":     "1",
	}
	return ws.conn.WriteJSON(joinMsg)
}

func (ws *WSClient) LeaveSession(sessionID string) error {
	leaveMsg := map[string]interface{}{
		"topic":   "session:" + sessionID,
		"event":   "phx_leave",
		"payload": map[string]interface{}{},
		"ref":     "2",
	}
	return ws.conn.WriteJSON(leaveMsg)
}

func (ws *WSClient) Ping() (int64, error) {
	pingMsg := map[string]interface{}{
		"topic":   "phoenix",
		"event":   "ping",
		"payload": map[string]interface{}{},
		"ref":     "3",
	}
	if err := ws.conn.WriteJSON(pingMsg); err != nil {
		return 0, err
	}
	return time.Now().UnixMilli(), nil
}

func (ws *WSClient) Close() {
	close(ws.done)
	ws.conn.Close()
}

func (c *Client) Close() {
	if c.wsConn != nil {
		c.wsConn.Close()
	}
}
