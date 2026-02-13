---
date: 2026-02-13
author: Lem
version: 1.1
status: draft
replaces: product-brief-agent_monitor-2026-02-03.md
---

# Product Requirements Document: Babysitter

## Executive Summary

**Babysitter** is a workflow orchestration engine for AI coding agents. It keeps terminal sessions alive, sequences work across td issues, and intelligently guides development from one task to the next—enabling autonomous, multi-step development workflows that can run overnight or across multiple sessions.

Unlike the original vision of a comprehensive agent monitoring platform, babysitter has a narrower focus: **orchestration**. Task management is handled by [td](https://github.com/marcus/td). Visibility is handled by [sidecar](https://github.com/marcus/sidecar). Babysitter fills the gap: **executing workflows, managing agent sessions, and providing intelligent intervention when things go wrong.**

---

## The Ecosystem

Babysitter is part of a three-tool ecosystem:

| Tool | Responsibility | Technology |
|------|---------------|------------|
| **td** | Task management, handoffs, session tracking | Go (CLI) |
| **sidecar** | Visibility layer, TUI dashboard, conversation history | Go (Bubble Tea) |
| **babysitter** | Workflow orchestration, session management, intervention | Elixir (daemon) + Go (TUI/plugin) |

**Integration points:**
- Babysitter reads td issues as workflow nodes
- Babysitter writes logs/handoffs back to td
- Sidecar or standalone TUI displays babysitter status
- TUI can trigger/cancel workflows
- Babysitter handles git commits/PRs based on config

---

## Problem Statement

### The Gap

After setting up td for task management and sidecar for visibility, a critical gap remains: **nothing connects the tasks to actual execution**.

You have:
- A backlog of issues in td
- A dashboard in sidecar showing what's happening
- An AI coding agent (Claude Code, OpenCode, Cursor, etc.)

But you still need to:
- Manually start each session
- Monitor for completion (or false completion)
- Decide what to work on next
- Restart when things crash or get stuck
- Track progress across multiple sessions

### Pain Points

1. **Manual session management** - Starting agents, watching output, knowing when to move on
2. **No workflow sequencing** - td tells you *what* to do, but not *how to chain it together*
3. **False completion** - Agents claim "DONE" but work is incomplete
4. **Failure recovery** - OOM crashes, hangs, and errors halt everything
5. **Context loss** - When a session ends, the next one doesn't know what happened
6. **No overnight autonomy** - Can't go to bed and trust work will continue

### What Babysitter Does

Babysitter is the **execution layer** that:
- Keeps terminal processes alive
- Runs workflows defined by td issues + YAML configs
- Detects completion (real or false)
- Intervenes when stuck (dumb rules or LLM-powered)
- Chains tasks together automatically
- Enables overnight autonomous runs

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    VISIBILITY OPTIONS                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ SIDECAR (Go)                                            │   │
│  │ ┌──────────┐ ┌──────────┐ ┌──────────────────────────┐ │   │
│  │ │   Git    │ │   TD     │ │  Babysitter Plugin       │ │   │
│  │ │  Plugin  │ │ Monitor  │ │  (embedded TUI)          │ │   │
│  │ └──────────┘ └──────────┘ └──────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            OR                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ STANDALONE TUI (Go)                                     │   │
│  │ $ babysitter-tui                                        │   │
│  │ - Same UI, no sidecar required                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                    │
                             HTTP/WebSocket
                                    │
┌────────────────────────────────────────────────────│─────────────┐
│                    BABYSITTER DAEMON (Elixir)     │             │
│  ┌─────────────────────────────────────────────────┴──────────┐ │
│  │                     API Layer (Phoenix)                     │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                 │                               │
│  ┌──────────────────────────────┴─────────────────────────────┐ │
│  │                  Workflow Engine (GenServer)                │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────────┐  │ │
│  │  │  Workflow   │ │   Session   │ │     Intervention     │  │ │
│  │  │  Supervisor │ │   Manager   │ │       Engine         │  │ │
│  │  └─────────────┘ └─────────────┘ └──────────────────────┘  │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                 │                               │
│  ┌──────────────────────────────┴─────────────────────────────┐ │
│  │                 Session Process (GenServer per agent)       │ │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────────────────┐  │ │
│  │  │   Agent    │ │   Output   │ │      State             │  │ │
│  │  │  Process   │ │   Parser   │ │      Machine           │  │ │
│  │  │ (Port)     │ │            │ │                        │  │ │
│  │  └────────────┘ └────────────┘ └────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   TD Integration (read td SQLite)           │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    │ spawns
                                    ▼
                    ┌───────────────────────────────┐
                    │     AGENT SESSION (tmux)      │
                    │  ┌─────────────────────────┐  │
                    │  │   claude / opencode /   │  │
                    │  │   cursor --headless     │  │
                    │  └─────────────────────────┘  │
                    └───────────────────────────────┘
```

### Technology Decisions

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Orchestration daemon | **Elixir** | BEAM's supervision trees ideal for managing long-running processes, fault tolerance, hot code reloading |
| Session management | **tmux** | Attachable sessions, survives daemon restart, cross-platform |
| TUI / Sidecar plugin | **Go** | Bubble Tea TUI; works standalone or embedded in sidecar |
| Configuration | **YAML** | Familiar CI-like syntax, easy to edit |
| State storage | **SQLite** (via td) | Reuses td's database, single source of truth |
| API | **Phoenix** | WebSocket for real-time updates, JSON API for TUI |

### Why Hybrid Go + Elixir?

**Elixir for orchestration:**
- Supervision trees handle process crashes gracefully
- OTP provides battle-tested patterns for long-running processes
- Hot code reloading enables updates without stopping workflows
- Lightweight processes (green threads) for many concurrent sessions

**Go for sidecar plugin:**
- Sidecar is Go; plugin must be Go
- Shared code with sidecar internals
- Type-safe JSON client for babysitter API

---

## Core Concepts

### Workflow

A workflow is a directed graph of **stages** that defines how work progresses. Workflows are defined in YAML files and reference td issues.

```yaml
# .babysitter/workflows/default.yaml
name: feature-development
description: Standard feature development workflow

stages:
  - id: planning
    td_query: "status = open AND type = feature AND priority <= P1"
    max_issues: 1
    on_complete: implementation
    
  - id: implementation
    agent: claude
    prompt_template: |
      Implement the feature described in td issue {{issue.id}}.
      Title: {{issue.title}}
      Context from handoff: {{issue.last_handoff.remaining}}
    timeout: 30m
    validation:
      - type: compile
      - type: tests
      - type: command
        command: "npm run lint"
    on_success: review
    on_failure: retry
    max_retries: 2
    
  - id: review
    agent: claude
    prompt: "Review your implementation of {{issue.id}}. Check for edge cases and errors."
    timeout: 10m
    on_success: complete
    
  - id: complete
    action: td_review
    message: "Implementation complete, ready for human review"
    
  - id: retry
    action: restart_stage
    stage: implementation
    with_context: true

transitions:
  planning -> implementation -> review -> complete
  implementation -> retry -> implementation  # loop back
```

### Session

A session is a running agent process managed by babysitter. Sessions:
- Run inside tmux (attachable for debugging)
- Have their stdout/stderr captured and parsed
- Maintain state (current stage, retries, output history)
- Can be killed, restarted, or paused

### Stage

A stage is a single step in a workflow. Types:

| Type | Description |
|------|-------------|
| `agent` | Run an AI agent with a prompt |
| `action` | Execute a system action (td commands, shell commands) |
| `validation` | Run validation checks (compile, tests, lint) |
| `decision` | LLM-powered decision point |
| `parallel` | Run multiple stages concurrently |

### Intervention

When a session gets stuck or fails validation, babysitter can intervene:

**Dumb intervention** (rules-based):
- Max retries exceeded -> escalate to human
- Timeout -> kill and restart with context
- Validation failed -> retry with error message

**Smart intervention** (LLM-powered):
- Analyze session output to diagnose problem
- Generate modified prompt with troubleshooting context
- Decide whether to retry, skip, or escalate

### Intelligence Level

Each workflow or stage can specify an intelligence level:

```yaml
intelligence: dumb  # rules-based only, no LLM calls
intelligence: smart  # LLM analyzes and decides
intelligence: hybrid  # dumb for happy path, smart on failure
```

---

## Data Models

### Workflow Definition

```yaml
# Stored in .babysitter/workflows/<name>.yaml
id: string
name: string
description: string
intelligence: dumb | smart | hybrid
stages: Stage[]
transitions: map<stage_id, stage_id[]>
```

### Stage

```yaml
id: string
type: agent | action | validation | decision | parallel
# For agent type:
agent: claude | opencode | cursor | custom
prompt: string | prompt_template
timeout: duration
# For validation type:
validation: Validation[]
# Transitions:
on_success: stage_id
on_failure: stage_id
on_timeout: stage_id
max_retries: int
```

### Session State

Stored in babysitter's ETS/Mnesia, persisted to SQLite for recovery:

```elixir
%Session{
  id: UUID,
  workflow_id: string,
  current_stage: string,
  issue_id: string,  # td issue being worked
  status: :running | :paused | :completed | :failed | :escalated,
  started_at: datetime,
  tmux_session: string,
  output_buffer: [output_entry],
  retries: %{stage_id => count},
  context: map,  # variables passed between stages
  intelligence_level: :dumb | :smart | :hybrid
}
```

### Output Entry

```elixir
%OutputEntry{
  timestamp: datetime,
  type: :stdout | :stderr | :system,
  content: string,
  parsed: map  # extracted signals (errors, completion markers, etc.)
}
```

### Validation Result

```elixir
%ValidationResult{
  type: :compile | :tests | :lint | :command,
  status: :pass | :fail,
  output: string,
  duration_ms: int,
  artifacts: [file_path]  # generated files, logs, etc.
}
```

---

## API Contracts

### REST API

**GET /api/workflows**
```json
{
  "workflows": [
    {"id": "default", "name": "Feature Development", "status": "idle"},
    {"id": "bugfix", "name": "Bug Fix Pipeline", "status": "running"}
  ]
}
```

**POST /api/workflows/{id}/start**
```json
// Request
{
  "issue_id": "td-a1b2",  // optional, will query td if not provided
  "intelligence": "smart"  // override workflow default
}

// Response
{
  "session_id": "sess-abc123",
  "workflow_id": "default",
  "issue_id": "td-a1b2",
  "status": "running"
}
```

**GET /api/sessions/{id}**
```json
{
  "id": "sess-abc123",
  "workflow_id": "default",
  "issue_id": "td-a1b2",
  "current_stage": "implementation",
  "status": "running",
  "started_at": "2026-02-13T10:30:00Z",
  "tmux_session": "babysitter-sess-abc123",
  "retries": {"implementation": 1},
  "context": {
    "planning_complete": true,
    "last_error": "npm run lint failed"
  }
}
```

**GET /api/sessions/{id}/output**
```json
{
  "entries": [
    {
      "timestamp": "2026-02-13T10:31:05Z",
      "type": "stdout",
      "content": "Implementing OAuth callback...",
      "parsed": {"signal": "progress"}
    },
    {
      "timestamp": "2026-02-13T10:35:22Z", 
      "type": "stderr",
      "content": "Error: Cannot find module 'oauth'",
      "parsed": {"signal": "error", "error_type": "module_not_found"}
    }
  ],
  "cursor": "entry-456"
}
```

**POST /api/sessions/{id}/intervene**
```json
// Request
{
  "action": "retry" | "skip" | "escalate" | "custom",
  "message": "Try installing the oauth package first",
  "restart_from": "implementation"  // optional
}

// Response
{
  "status": "intervention_applied",
  "new_stage": "implementation"
}
```

**POST /api/sessions/{id}/attach**
Returns tmux attach command:
```json
{
  "command": "tmux attach -t babysitter-sess-abc123"
}
```

### WebSocket Events

Real-time updates sent to sidecar plugin:

```elixir
# Session started
%{event: "session:started", session: %{...}}

# Stage transition
%{event: "session:stage", session_id: "...", stage: "implementation"}

# Output chunk
%{event: "session:output", session_id: "...", entry: %{...}}

# Validation result
%{event: "session:validation", session_id: "...", result: %{...}}

# Intervention triggered
%{event: "session:intervention", session_id: "...", reason: "max_retries", action: "escalate"}

# Session completed
%{event: "session:completed", session_id: "...", issue_id: "...", status: "success"}
```

---

## TD Integration

### Reading Issues

Babysitter reads directly from td's SQLite database at `.todos/issues.db`:

```elixir
# lib/babysitter/td/client.ex
defmodule Babysitter.TD.Client do
  def query_issues(query) do
    # Parse TDQ query and execute against SQLite
    # Returns matching issues with handoff context
  end
  
  def get_issue(issue_id) do
    # Get single issue with full context (logs, handoffs, files)
  end
end
```

### Writing Updates

Babysitter uses td CLI for writes (respects hooks/validation):

```elixir
def log_progress(issue_id, message) do
  System.cmd("td", ["log", message, "--issue", issue_id])
end

def create_handoff(issue_id, opts) do
  args = ["handoff", issue_id, 
          "--done", opts[:done],
          "--remaining", opts[:remaining]]
  System.cmd("td", args)
end

def submit_review(issue_id) do
  System.cmd("td", ["review", issue_id])
end
```

### Issue as Workflow Context

td issues provide context to agents:

```yaml
prompt_template: |
  You are continuing work on a feature.
  
  **TD Issue**: {{issue.id}}
  **Title**: {{issue.title}}
  **Description**: {{issue.description}}
  
  **Previous Handoff** ({{issue.last_handoff.timestamp}}):
  - Done: {{issue.last_handoff.done}}
  - Remaining: {{issue.last_handoff.remaining}}
  - Decisions: {{issue.last_handoff.decisions}}
  - Uncertain: {{issue.last_handoff.uncertain}}
  
  Continue from where the previous session left off.
```

---

## Sidecar Plugin

The babysitter sidecar plugin provides visibility and control.

### UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│  BABYSITTER                                    [R] Refresh  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ACTIVE SESSIONS                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ sess-abc123  td-a1b2  [implementation]  12m ago     │   │
│  │ Implementing OAuth callback...                       │   │
│  │ ⚠ validation failed (lint) - retrying               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ sess-def456  td-c3d4  [review]  5m ago              │   │
│  │ Reviewing implementation...                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  QUEUED (next 3)                                            │
│  • td-e5f6 "Add rate limiting" (P1, feature)               │
│  • td-g7h8 "Fix memory leak" (P1, bug)                     │
│  • td-i9j0 "Update dependencies" (P2, chore)               │
│                                                             │
│  RECENTLY COMPLETED (today)                                 │
│  ✓ td-x1y2 "OAuth login" - 2h ago                          │
│  ✓ td-z3a4 "Token refresh" - 4h ago                        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [E] Escalate  [A] Attach  [S] Skip  [N] New Workflow       │
└─────────────────────────────────────────────────────────────┘
```

### Plugin Interface

```go
// internal/plugins/babysitter/plugin.go
package babysitter

type Plugin struct {
    id       string
    name     string
    client   *Client  // HTTP client to babysitter daemon
    sessions []Session
    focused  bool
}

func (p *Plugin) Init(ctx *plugin.Context) error {
    p.client = NewClient("http://localhost:4001")
    go p.subscribe()
    return nil
}

func (p *Plugin) Update(msg tea.Msg) (plugin.Plugin, tea.Cmd) {
    switch m := msg.(type) {
    case SessionUpdateMsg:
        p.updateSession(m.Session)
    case OutputMsg:
        p.appendOutput(m.SessionID, m.Entry)
    }
    return p, nil
}

func (p *Plugin) Commands() []plugin.Command {
    return []plugin.Command{
        {ID: "escalate", Name: "Escalate", Handler: p.escalateCurrent},
        {ID: "attach", Name: "Attach", Handler: p.attachToSession},
        {ID: "skip", Name: "Skip Stage", Handler: p.skipStage},
        {ID: "new", Name: "New Workflow", Handler: p.newWorkflow},
    }
}
```

### Standalone TUI Mode

The Go component can run as a standalone TUI without sidecar:

```bash
# Run as standalone dashboard
babysitter-tui

# Connect to daemon on custom host/port
babysitter-tui --daemon http://localhost:4001
```

**Architecture:**

```
go/
├── cmd/
│   └── babysitter-tui/        # Standalone binary
│       └── main.go
├── internal/
│   ├── client/                # Shared HTTP/WS client
│   ├── tui/                   # Shared TUI components
│   └── plugin/                # Sidecar plugin adapter
└── pkg/
    └── plugin/                # Sidecar plugin exports
```

The standalone TUI and sidecar plugin share the same client and UI code. The plugin simply wraps the TUI in sidecar's plugin interface.

---

## Git Integration & Commit Strategy

Babysitter provides configurable logic for when and how to commit changes and open PRs.

### Commit Normalization

Configure how commits are normalized and formatted:

```yaml
# ~/.config/babysitter/config.yaml
git:
  commit_strategy:
    # When to commit
    trigger: stage_complete | validation_pass | manual | smart
    
    # Commit message format
    message_template: |
      {{issue.id}}: {{issue.title}}
      
      {{stage.summary}}
      
      Co-authored-by: Babysitter <babysitter@local>
    
    # Normalize commits (squash related changes)
    normalize:
      enabled: true
      squash_pattern: "^(fixup|wip|tmp)"
      max_age_hours: 24
      
    # Sign commits
    gpg_sign: false
    gpg_key_id: null
```

### PR Strategy

Control when PRs are created and their content:

```yaml
git:
  pr_strategy:
    # When to create PR
    trigger: workflow_complete | validation_pass | manual
    
    # PR template
    title_template: "{{issue.id}}: {{issue.title}}"
    body_template: |
      ## Summary
      {{workflow.summary}}
      
      ## Changes
      {{git.diff_summary}}
      
      ## Test Plan
      {{workflow.test_plan}}
      
      Closes #{{issue.id}}
    
    # Branch naming
    branch_template: "{{issue.type}}/{{issue.id}}-{{issue.title | slugify}}"
    
    # Reviewers (can be smart)
    reviewers:
      - "{{issue.implementer}}"  # Auto-assign implementer
    
    # Labels based on issue type
    labels:
      feature: ["enhancement"]
      bug: ["bug", "needs-review"]
      chore: ["maintenance"]
```

### Smart Commit Actions

When `intelligence: smart`, babysitter can make intelligent commit decisions:

```yaml
stages:
  - id: smart_commit
    type: action
    action: smart_commit
    config:
      # Let LLM decide commit timing and message
      analyze_changes: true
      group_related: true
      message_style: conventional  # conventional | descriptive | minimal
```

---

## Session Management

### tmux Integration

Sessions run in tmux for attachability:

```elixir
defmodule Babysitter.SessionManager do
  def start_session(session_id, agent, prompt) do
    tmux_name = "babysitter-#{session_id}"
    
    # Create tmux session
    System.cmd("tmux", ["new-session", "-d", "-s", tmux_name])
    
    # Start agent in tmux
    cmd = build_agent_command(agent, prompt)
    System.cmd("tmux", ["send-keys", "-t", tmux_name, cmd, "C-m"])
    
    # Start output capture process
    spawn_output_capture(session_id, tmux_name)
    
    {:ok, tmux_name}
  end
  
  def attach_command(session_id) do
    "tmux attach -t babysitter-#{session_id}"
  end
  
  def kill_session(session_id) do
    System.cmd("tmux", ["kill-session", "-t", "babysitter-#{session_id}"])
  end
end
```

### Output Capture

```elixir
defp spawn_output_capture(session_id, tmux_name) do
  spawn(fn ->
    {:ok, pid, os_pid} = :exec.run("tmux pipe-pane -t #{tmux_name} -o cat", [:stdout, :stderr])
    
    receive do
      {:stdout, ^os_pid, data} ->
        Babysitter.OutputParser.process(session_id, data)
      {:stderr, ^os_pid, data} ->
        Babysitter.OutputParser.process(session_id, data)
    end
  end)
end
```

### Output Parsing

Extract signals from agent output:

```elixir
defmodule Babysitter.OutputParser do
  @completion_patterns [
    ~r/DONE.*implementation complete/i,
    ~r/✓ All changes committed/i,
    ~r/Successfully completed/i
  ]
  
  @error_patterns [
    ~r/Error: (.+)/,
    ~r/FATAL: (.+)/,
    ~r/Failed to (.+)/
  ]
  
  def process(session_id, output) do
    # Store raw output
    Babysitter.Session.append_output(session_id, output)
    
    # Check for signals
    cond do
      matches_pattern?(output, @completion_patterns) ->
        Babysitter.Session.signal_completion(session_id)
        
      matches_pattern?(output, @error_patterns) ->
        Babysitter.Session.signal_error(session_id, extract_error(output))
        
      true ->
        :ok
    end
  end
end
```

---

## Intervention Engine

### Dumb Intervention (Rules-Based)

```elixir
defmodule Babysitter.Intervention.Dumb do
  def check(session) do
    cond do
      session.retries[session.current_stage] >= session.max_retries ->
        {:escalate, "Max retries exceeded"}
        
      session.status == :timeout ->
        {:restart, "Session timed out, restarting with context"}
        
      has_validation_failure?(session) ->
        {:retry, "Validation failed", with_context: last_error(session)}
        
      stuck_too_long?(session) ->
        {:intervene, "No progress for #{stuck_duration(session)}"}
        
      true ->
        :ok
    end
  end
end
```

### Smart Intervention (LLM-Powered)

```elixir
defmodule Babysitter.Intervention.Smart do
  def analyze(session) do
    prompt = """
    Analyze this agent session and recommend next steps.
    
    ## Session Context
    - Issue: #{session.issue_id}
    - Current Stage: #{session.current_stage}
    - Retries: #{session.retries[session.current_stage]}
    
    ## Recent Output
    ```
    #{last_n_lines(session.output, 100)}
    ```
    
    ## Validation Results
    #{format_validations(session.validations)}
    
    Respond with:
    1. DIAGNOSIS: What went wrong?
    2. ACTION: retry | skip | escalate | custom
    3. CONTEXT: Modified prompt or message if custom action
    """
    
    case LLM.generate(prompt) do
      {:ok, response} -> parse_intervention(response)
      {:error, _} -> {:fallback, Dumb.check(session)}
    end
  end
end
```

### Hybrid Mode

```elixir
def intervene(session) do
  case session.intelligence_level do
    :dumb -> Dumb.check(session)
    :smart -> Smart.analyze(session)
    :hybrid ->
      case Dumb.check(session) do
        :ok -> Smart.analyze(session)  # Only use LLM if dumb found nothing
        result -> result
      end
  end
end
```

---

## MVP Scope

### In Scope

**Core Orchestration**
- [ ] Elixir daemon with Phoenix API
- [ ] Workflow definition parsing (YAML)
- [ ] Stage execution engine
- [ ] Session management via tmux
- [ ] Output capture and parsing

**TD Integration**
- [ ] Read issues from td SQLite
- [ ] Write logs/handoffs via td CLI
- [ ] Query-based issue selection

**Intervention**
- [ ] Dumb intervention (rules-based)
- [ ] Timeout handling
- [ ] Retry logic
- [ ] Escalation to human

**Sidecar Plugin / Standalone TUI**
- [ ] Session list view
- [ ] Output streaming
- [ ] Basic controls (start, stop, attach)
- [ ] Standalone binary option (no sidecar required)

**Git Integration**
- [ ] Configurable commit triggers
- [ ] Commit message templates
- [ ] PR creation (manual trigger)

**Validation**
- [ ] Compile check
- [ ] Test run
- [ ] Custom command execution

### Out of Scope (Post-MVP)

- Smart intervention (LLM-powered analysis)
- Parallel workflow execution
- Visual workflow builder
- Multi-project support
- Browser-based validation
- Marketplace for workflow templates

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

1. **Project Setup**
   - Create Elixir project with Phoenix
   - Set up supervision tree structure
   - Add tmux integration module

2. **Session Management**
   - Implement `SessionManager` GenServer
   - Create tmux session spawning
   - Basic output capture

3. **API Layer**
   - Phoenix endpoints for sessions
   - WebSocket for real-time updates
   - Basic health/status endpoints

### Phase 2: Workflow Engine (Week 2)

1. **Workflow Definition**
   - YAML parser for workflow files
   - Stage type implementations
   - Transition logic

2. **TD Integration**
   - SQLite reader for td issues
   - CLI wrapper for writes
   - Context extraction from handoffs

3. **Execution**
   - Run agent with prompt
   - Track stage progress
   - Handle stage completion

### Phase 3: Intervention & Validation (Week 3)

1. **Validation**
   - Compile check stage
   - Test run stage
   - Custom command stage

2. **Dumb Intervention**
   - Retry logic
   - Timeout handling
   - Escalation triggers

3. **Output Parsing**
   - Completion signal detection
   - Error extraction
   - Progress tracking

### Phase 4: TUI & Plugin (Week 4)

1. **TUI Implementation**
   - Create Go TUI package with Bubble Tea
   - HTTP client for daemon
   - Session list, output, controls

2. **Standalone Binary**
   - Build standalone `babysitter-tui` binary
   - Command-line flags for daemon connection
   
3. **Sidecar Plugin**
   - Wrap TUI in sidecar plugin interface
   - Register with sidecar plugin registry

4. **Real-time Updates**
   - WebSocket subscription
   - Session state sync
   - Output streaming

5. **Controls**
   - Start/stop workflow
   - Attach to session
   - Manual intervention

### Phase 5: Polish & Testing (Week 5)

1. **Error Handling**
   - Graceful degradation
   - Recovery from crashes
   - State persistence

2. **Documentation**
   - API documentation
   - Workflow configuration guide
   - Troubleshooting guide

3. **Testing**
   - Unit tests for core modules
   - Integration tests for workflows
   - End-to-end test scenarios

---

## Configuration

### Daemon Configuration

```yaml
# ~/.config/babysitter/config.yaml
daemon:
  port: 4001
  log_level: info

tmux:
  base_session: babysitter

td:
  database: .todos/issues.db

agents:
  claude:
    command: claude
    args: ["--dangerously-skip-permissions"]
  opencode:
    command: opencode
    args: []
  cursor:
    command: cursor-agent
    args: ["--headless"]

git:
  commit_strategy:
    trigger: stage_complete
    message_template: |
      {{issue.id}}: {{issue.title}}
      
      {{stage.summary}}
  pr_strategy:
    trigger: manual

intervention:
  default_intelligence: hybrid
  max_retries: 3
  timeout_minutes: 30
  stuck_threshold_minutes: 10
```

### Workflow Configuration

```yaml
# .babysitter/workflows/bugfix.yaml
name: Bug Fix Pipeline
description: Standard workflow for fixing bugs

intelligence: hybrid

stages:
  - id: reproduce
    type: agent
    agent: claude
    prompt_template: |
      Reproduce the bug described in issue {{issue.id}}.
      Title: {{issue.title}}
      Description: {{issue.description}}
      
      First, understand the bug by reading relevant code.
      Then, create a minimal reproduction case.
      
      Report your findings clearly.
    timeout: 15m
    on_success: fix
    on_failure: escalate
    
  - id: fix
    type: agent
    agent: claude
    prompt_template: |
      Fix the bug identified in the reproduce stage.
      
      Previous findings:
      {{context.reproduce_findings}}
      
      Make the minimal fix that addresses the root cause.
      Ensure the fix doesn't break existing tests.
    timeout: 30m
    validation:
      - type: tests
      - type: command
        command: "npm run lint"
    on_success: verify
    on_failure: retry
    max_retries: 2
    
  - id: verify
    type: agent
    agent: claude
    prompt: |
      Verify that {{issue.id}} is actually fixed.
      
      1. Run the reproduction case
      2. Confirm the bug no longer occurs
      3. Run the full test suite
      
      Report whether the fix is complete.
    timeout: 15m
    on_success: complete
    on_failure: fix  # go back to fix stage
    
  - id: complete
    type: action
    action: td_review
    message: "Bug fix complete, ready for review"
    
  - id: escalate
    type: action
    action: td_handoff
    done: "Attempted to reproduce bug"
    remaining: "{{issue.title}} - needs manual investigation"
    uncertain: "Could not reproduce automatically"

entry_point: reproduce
```

---

## Success Metrics

### MVP Success Criteria

**Functionality**
- Can run a 3-stage workflow end-to-end without manual intervention
- Sessions survive daemon restart (via tmux)
- Can attach to running session for debugging
- Dumb intervention correctly handles timeouts and max retries

**Integration**
- Reads td issues correctly
- Writes handoffs that are useful for next session
- Sidecar plugin shows accurate status
- WebSocket updates arrive within 1 second of events

**Reliability**
- Daemon stays up for 24+ hours without crash
- Failed sessions are properly cleaned up
- No orphaned tmux sessions
- State persists across daemon restarts

### Post-MVP Goals

- Overnight autonomous runs completing 5+ issues
- Smart intervention reduces escalation rate by 50%
- False completion detection catches 90%+ of incomplete work
- Community workflow templates available

---

## File Structure

```
babysitter/
├── elixir/                          # Elixir daemon
│   ├── lib/
│   │   ├── babysitter/
│   │   │   ├── application.ex
│   │   │   ├── api/                 # Phoenix controllers
│   │   │   │   ├── session_controller.ex
│   │   │   │   ├── workflow_controller.ex
│   │   │   │   └── websocket_handler.ex
│   │   │   ├── workflow/            # Workflow engine
│   │   │   │   ├── engine.ex
│   │   │   │   ├── stage.ex
│   │   │   │   ├── parser.ex
│   │   │   │   └── validator.ex
│   │   │   ├── session/             # Session management
│   │   │   │   ├── manager.ex
│   │   │   │   ├── process.ex
│   │   │   │   └── output_parser.ex
│   │   │   ├── intervention/        # Intervention engine
│   │   │   │   ├── dumb.ex
│   │   │   │   ├── smart.ex
│   │   │   │   └── engine.ex
│   │   │   ├── td/                  # TD integration
│   │   │   │   ├── client.ex
│   │   │   │   └── context.ex
│   │   │   └── tmux/                # tmux integration
│   │   │       └── session.ex
│   │   └── babysitter.ex
│   ├── config/
│   ├── test/
│   └── mix.exs
│
├── go/                              # Go components
│   ├── cmd/
│   │   └── babysitter-tui/          # Standalone TUI binary
│   │       └── main.go
│   └── internal/
│       ├── client/                  # HTTP/WebSocket client
│       ├── tui/                     # Shared TUI components
│       │   ├── sessions.go
│       │   ├── output.go
│       │   └── controls.go
│       └── sidecar/                 # Sidecar plugin
│           └── plugin.go
│
├── docs/
│   ├── prd-babysitter-2026-02-13.md # This document
│   ├── api-reference.md
│   ├── workflow-guide.md
│   └── troubleshooting.md
│
└── .babysitter/
    └── workflows/
        ├── default.yaml
        ├── bugfix.yaml
        └── feature.yaml
```

---

## Design Decisions

### 1. Agent Authentication & Model Selection

**Decision:** Use global config for API keys. Prompt user if not configured. Support per-step model/provider customization.

```yaml
# ~/.config/babysitter/config.yaml
providers:
  anthropic:
    api_key: "${ANTHROPIC_API_KEY}"  # Read from env
    default_model: "claude-sonnet-4-20250514"
  openai:
    api_key: "${OPENAI_API_KEY}"
    default_model: "gpt-4.1"
  openrouter:
    api_key: "${OPENROUTER_API_KEY}"
    
# Per-workflow model selection
workflows:
  code_review:
    stages:
      - id: review
        agent:
          provider: anthropic
          model: "claude-opus-4-20250514"  # Use Opus for complex reviews
        
  quick_fix:
    stages:
      - id: fix
        agent:
          provider: openai
          model: "gpt-4.1-mini"  # Faster/cheaper for simple fixes
```

### 2. Concurrent Sessions & Rate Limits

**Decision:** User-configurable parallelism with recommendations and fallbacks.

```yaml
concurrency:
  max_parallel_sessions: 3  # User sets this
  
  # System recommendations (shown in UI)
  recommendations:
    memory_gb_per_session: 4
    warning_threshold: 8  # Warn if total would exceed
  
  # Rate limit handling
  rate_limits:
    anthropic:
      requests_per_minute: 60
      tokens_per_minute: 400000
    openai:
      requests_per_minute: 500
      
  # Fallback behavior when limits hit
  on_rate_limit:
    action: queue  # queue | throttle | fallback_provider
    fallback_provider: openai  # Optional alternate
    retry_after_header: true
```

### 3. Detecting Meaningful Progress

**Decision:** Combine td state analysis with optional smart intervention. Primary signals from issue cycles and review feedback.

```yaml
progress_detection:
  # Primary: td issue state analysis
  td_signals:
    max_cycles_per_stage: 3      # Escalate if looping >3 times
    review_feedback_weight: high # If reviews keep rejecting, flag it
    handoff_patterns: true       # Detect repetitive handoffs
    
  # Secondary: optional git/file analysis
  git_signals:
    enabled: false  # Can enable for deeper analysis
    track_file_changes: true
    diff_analysis: false
    
  # Smart intervention hook
  smart_action:
    trigger: "cycles > 2 OR stuck_duration > 20m"
    prompt: |
      Are we swirling here? Can I help unstick things?
      Analyze the issue: {{issue.id}}
      Recent attempts: {{context.attempts}}
      Review feedback: {{context.review_feedback}}
```

### 4. Inter-Issue Dependencies

**Decision:** Workflows MUST respect td dependencies and use them for ordering.

```yaml
workflow:
  respect_dependencies: true  # Always true, not configurable
  
  # Dependency-based scheduling
  scheduling:
    strategy: critical_path   # Use td's critical-path logic
    auto_detect_deps: true    # Read from td dep commands
    
  # When dependency is blocked
  on_blocked:
    action: skip_and_queue    # Skip, queue next available
    retry_blocked_after: 5m   # Re-check blocked deps periodically
```

---

## Resolved Questions

These questions were addressed during initial planning:

1. **How to handle agent authentication?**
   - **Resolution:** Use global config with env var support. Prompt if missing. Allow per-step model/provider override.

2. **How to handle multiple concurrent sessions?**
   - **Resolution:** User-configurable parallelism with memory/rate limit warnings and fallback providers.

3. **How to detect "meaningful progress"?**
   - **Resolution:** Primary signals from td issue state (cycles, reviews, handoffs). Optional smart intervention for "stuck" detection.

4. **How to handle inter-issue dependencies?**
   - **Resolution:** Workflows respect td dependencies automatically. Use critical-path scheduling.

---

## Open Questions

Questions to address during implementation:

1. **How should the standalone TUI be distributed?**
   - Separate binary or bundled with daemon?
   - Homebrew formula structure?

2. **What's the default commit trigger for MVP?**
   - `stage_complete` seems most predictable
   - But `smart` might reduce commit noise

3. **Should babysitter create a `.babysitter/` directory in projects?**
   - Or keep all config in `~/.config/babysitter/`?
   - Project-level workflows vs global?

---

## References

- [td Repository](https://github.com/marcus/td)
- [sidecar Repository](https://github.com/marcus/sidecar)
- Original product brief: `product-brief-agent_monitor-2026-02-03.md`
