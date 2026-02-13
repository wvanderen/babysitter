package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/gorilla/websocket"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
	wsConn     *websocket.Conn
}

func New(baseURL string) *Client {
	return &Client{
		baseURL:    baseURL,
		httpClient: &http.Client{},
	}
}

type Session struct {
	ID           string                 `json:"id"`
	WorkflowID   string                 `json:"workflow_id"`
	IssueID      string                 `json:"issue_id"`
	CurrentStage string                 `json:"current_stage"`
	Status       string                 `json:"status"`
	StartedAt    string                 `json:"started_at"`
	TmuxSession  string                 `json:"tmux_session"`
	Retries      map[string]int         `json:"retries"`
	Context      map[string]interface{} `json:"context"`
}

type SessionList struct {
	Sessions []Session `json:"sessions"`
}

func (c *Client) ListSessions() (*SessionList, error) {
	resp, err := c.httpClient.Get(c.baseURL + "/api/sessions")
	if err != nil {
		return nil, fmt.Errorf("failed to list sessions: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var list SessionList
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &list, nil
}

func (c *Client) GetSession(id string) (*Session, error) {
	resp, err := c.httpClient.Get(fmt.Sprintf("%s/api/sessions/%s", c.baseURL, id))
	if err != nil {
		return nil, fmt.Errorf("failed to get session: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var sess Session
	if err := json.NewDecoder(resp.Body).Decode(&sess); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &sess, nil
}

func (c *Client) StartWorkflow(workflowID, issueID string) (*Session, error) {
	body := map[string]string{
		"issue_id": issueID,
	}
	jsonBody, _ := json.Marshal(body)

	resp, err := c.httpClient.Post(
		fmt.Sprintf("%s/api/workflows/%s/start", c.baseURL, workflowID),
		"application/json",
		bytes.NewReader(jsonBody),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to start workflow: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(respBody))
	}

	var sess Session
	if err := json.NewDecoder(resp.Body).Decode(&sess); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &sess, nil
}

func (c *Client) AttachCommand(sessionID string) (string, error) {
	resp, err := c.httpClient.Post(
		fmt.Sprintf("%s/api/sessions/%s/attach", c.baseURL, sessionID),
		"application/json",
		nil,
	)
	if err != nil {
		return "", fmt.Errorf("failed to get attach command: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		Command string `json:"command"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return result.Command, nil
}

type WSMessage struct {
	Event     string                 `json:"event"`
	SessionID string                 `json:"session_id,omitempty"`
	Session   *Session               `json:"session,omitempty"`
	Stage     string                 `json:"stage,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

func (c *Client) ConnectWebSocket(onMessage func(WSMessage)) error {
	wsURL := "ws" + c.baseURL[4:] + "/ws"

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return fmt.Errorf("failed to connect websocket: %w", err)
	}
	c.wsConn = conn

	go func() {
		defer conn.Close()
		for {
			var msg WSMessage
			if err := conn.ReadJSON(&msg); err != nil {
				return
			}
			onMessage(msg)
		}
	}()

	return nil
}

func (c *Client) Close() {
	if c.wsConn != nil {
		c.wsConn.Close()
	}
}
