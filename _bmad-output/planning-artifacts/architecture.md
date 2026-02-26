---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
workflowType: 'architecture'
lastStep: 8
status: 'complete'
completedAt: '2026-02-26'
inputDocuments:
  - docs/prd-babysitter-2026-02-13.md
  - docs/product-brief-agent_monitor-2026-02-03.md
  - _bmad-output/project-context.md
  - _bmad-output/planning-artifacts/research/technical-langgraph-integration-research-2026-02-24.md
workflowType: 'architecture'
project_name: 'babysitter'
user_name: 'Lem'
date: '2026-02-24'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

---

## Input Documents Loaded

| Document | Purpose |
|----------|---------|
| PRD (prd-babysitter-2026-02-13.md) | Product requirements, existing architecture |
| Product Brief (product-brief-agent_monitor-2026-02-03.md) | Original vision, success metrics |
| Project Context (project-context.md) | Implementation patterns, coding rules |
| LangGraph Research (technical-langgraph-integration-research-2026-02-24.md) | Technical research findings |

---

## Architecture Context

### Current System Architecture (Pre-LangGraph)

The babysitter system currently uses a Go TUI + Elixir/Phoenix architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                    VISIBILITY OPTIONS                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ STANDALONE TUI (Go)                                     │   │
│  │ $ babysitter-tui                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                     │
                              HTTP/WebSocket (Phoenix Channels)
                                     │
┌─────────────────────────────────────────────────────────────────┐
│                    BABYSITTER DAEMON (Elixir)                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                     API Layer (Phoenix)                    │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  Workflow Engine (GenServer)               │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                 Session Process (GenServer per agent)      │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   TD Integration (read td SQLite)          │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                     │
                                     │ spawns
                                     ▼
                     ┌───────────────────────────────┐
                     │     AGENT SESSION (tmux)      │
                     │  claude / opencode / cursor   │
                     └───────────────────────────────┘
```

### Why LangGraph Integration?

The PRD describes "dumb" and "smart" intervention patterns. LangGraph provides:

1. **Stateful Workflow Orchestration** - Better than hand-rolled GenServer workflows
2. **Human-in-the-Loop Patterns** - Built-in `interrupt/resume` for approvals
3. **Checkpointing** - Automatic state persistence for recovery
4. **MCP Tool Integration** - Standard protocol for agent tools
5. **Structured Agent Workflows** - Graph-based instead of linear stages

---

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
- **FR-1:** Workflow definition and execution (YAML-based stage graphs)
- **FR-2:** Session lifecycle management (tmux-based agent processes)
- **FR-3:** Output capture and parsing (signal detection, error extraction)
- **FR-4:** Intervention engine (dumb rules + smart LLM analysis)
- **FR-5:** TD integration (read issues, write logs/handoffs/reviews)
- **FR-6:** Git integration (commit triggers, PR creation)
- **FR-7:** Validation stages (compile, tests, lint, custom commands)
- **FR-8:** Real-time TUI updates (WebSocket streaming)
- **FR-9:** Human-in-the-loop patterns (approvals, escalation)
- **FR-10:** State persistence and recovery

**Non-Functional Requirements:**
- **NFR-1:** Fault tolerance - supervision trees, crash recovery
- **NFR-2:** Latency - WebSocket updates < 1 second (TUI↔Elixir only)
- **NFR-3:** Uptime - 24+ hours continuous operation
- **NFR-4:** State durability - survive daemon restarts
- **NFR-5:** Attachability - tmux sessions for debugging

**Scale & Complexity:**
- Primary domain: Distributed orchestration system
- Complexity level: Medium-High
- Estimated architectural components: 15-20

### Technical Constraints & Dependencies

| Constraint | Impact |
|------------|--------|
| tmux required | Session attachability, process isolation |
| td SQLite database | Single source of truth for issues |
| Phoenix Channels protocol | Go TUI must implement join/heartbeat |
| Elixir 1.19 / Phoenix 1.7 | OTP 27 features, supervision improvements |
| Go 1.25.5 / Bubble Tea | TUI framework constraints |
| LangGraph Python service | NEW - adds Python runtime dependency |

### Cross-Cutting Concerns Identified

1. **State Management** - Sessions, workflows, checkpoints need consistent persistence
2. **Error Handling** - Graceful degradation across Elixir/Go/Python boundaries
3. **Observability** - Logging, metrics, tracing across all components
4. **Security** - API keys, tmux session isolation, file permissions
5. **Testing** - Integration tests spanning all three languages

---

## Architectural Implications (Party Mode Analysis)

### Priority: Fault Isolation > Simplicity > Latency

Based on discussion with Winston (Architect), Amelia (Dev), and John (PM), the following architectural decisions are informed by prioritizing fault isolation first, then simplicity, with latency as acceptable trade-off.

### Fault Isolation Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FAULT ISOLATION LAYERS                      │
├─────────────────────────────────────────────────────────────────────┤
│  LAYER 1: Go TUI (user-facing, can restart independently)           │
│           └─ Crashes → user restarts, no data loss                  │
├─────────────────────────────────────────────────────────────────────┤
│  LAYER 2: Elixir/Phoenix (orchestration hub, state authority)       │
│           └─ Crashes → restarts via OTP, reconnects to LangGraph    │
│           └─ Owns: session state machine, tmux lifecycle            │
├─────────────────────────────────────────────────────────────────────┤
│  LAYER 3: LangGraph/Python (workflow intelligence, disposable)      │
│           └─ Crashes → Elixir recreates thread from checkpoint      │
│           └─ Owns: workflow graphs, interrupt/resume logic          │
├─────────────────────────────────────────────────────────────────────┤
│  LAYER 4: tmux/agents (isolated per session)                        │
│           └─ Crashes → Elixir detects, triggers intervention        │
└─────────────────────────────────────────────────────────────────────┘
```

### State Authority Model

**Principle:** Elixir remains the state authority. LangGraph is a stateless compute engine.

| Component | Owns | Responsibility |
|-----------|------|----------------|
| Elixir/Phoenix | Session state machine | Source of truth, tmux lifecycle |
| LangGraph | Workflow execution | Interrupt/resume, checkpointing |
| Go TUI | Local UI state | Display, user input |

**On LangGraph crash:** Elixir recreates thread from last known checkpoint.

### Communication Pattern

```
Go TUI ←→ Elixir/Phoenix ←→ LangGraph Server
   │           │                   │
   │  WebSocket│    REST + Poll    │
   │  (fast)   │     (simple)      │
   └───────────┴───────────────────┘
```

**Elixir ↔ LangGraph: REST + Polling (2-3s interval)**

Rationale: Simple, fault-tolerant. Latency acceptable for workflow decisions.

### Intervention Engine Split

| Type | Location | Rationale |
|------|----------|-----------|
| "Dumb" (rules-based) | Elixir | Fast, reliable, no external dependency |
| "Smart" (LLM-powered) | LangGraph | Isolated, can crash safely, has checkpoint context |

### State Synchronization

Elixir → LangGraph uses **eventual consistency**, not real-time sync:

```elixir
# Session state in Elixir (source of truth)
%Session{
  id: "sess-abc123",
  status: :running,           # Elixir's state machine
  langgraph_thread_id: "th-xyz789",
  langgraph_checkpoint_id: "cp-001",  # Last known checkpoint
}

# On LangGraph crash:
def handle_info({:langgraph_down, reason}, state) do
  {:ok, thread} = LangGraphClient.create_thread()
  {:ok, _} = LangGraphClient.restore_checkpoint(thread.id, state.checkpoint_id)
  {:noreply, %{state | langgraph_thread_id: thread.id}}
end
```

### Key Architectural Decisions

| Concern | Decision | Rationale |
|---------|----------|-----------|
| State authority | Elixir owns session state | OTP supervision, proven patterns |
| LangGraph role | Stateless workflow compute | Can crash, recreate from checkpoint |
| Elixir↔LangGraph | REST + polling (2-3s interval) | Simple, fault-tolerant |
| TUI↔Elixir | Phoenix Channels (existing) | Already implemented, works |
| Intervention split | Dumb=Elixir, Smart=LangGraph | Best of both layers |
| Latency tolerance | 2-3 seconds acceptable | Workflow decisions, not real-time UI |

### Three State Machines to Align

1. **Go TUI** - Local UI state
2. **Elixir Session** - GenServer state (source of truth)
3. **LangGraph Thread** - Checkpoint state

**Mapping required:** LangGraph `interrupt()` status → Elixir `:paused` state

---

## Starter Template Evaluation

### Existing Technology Stack (Already Implemented)

| Component | Technology | Status |
|-----------|------------|--------|
| Backend Daemon | Elixir 1.19 / Phoenix 1.7 | ✅ Existing |
| TUI | Go 1.25.5 / Bubble Tea | ✅ Existing |
| Session Management | tmux | ✅ Existing |
| State Storage | SQLite (via td) | ✅ Existing |

### NEW Component: LangGraph Python Service

The LangGraph service will handle:
- Workflow graph execution
- `interrupt/resume` for human-in-the-loop
- Smart intervention (LLM-powered analysis)
- Checkpointing for recovery

### Approach: Custom Structure (Not Template)

**Rationale:**
1. Templates assume LangGraph owns state authority - we need Elixir as source of truth
2. Templates include UI components - we only need API server
3. Our checkpointing needs differ (Elixir manages session→thread mapping)
4. Custom structure allows clean REST API contract with Elixir

### LangGraph Project Structure (Party Mode Revised)

```
langgraph/
├── src/
│   └── babysitter_agent/
│       ├── __init__.py
│       ├── graph.py              # Main workflow graph
│       ├── state.py              # State definitions (TypedDict)
│       ├── checkpointer.py       # Checkpoint config (SqliteSaver)
│       ├── nodes/
│       │   ├── __init__.py
│       │   ├── plan.py           # Planning/decision node
│       │   ├── execute.py        # Execute agent prompt
│       │   ├── validate.py       # Run validations
│       │   ├── review.py         # Self-review node
│       │   └── intervene.py      # Smart intervention (receives context)
│       ├── tools/
│       │   ├── __init__.py
│       │   └── mcp_tools.py      # MCP adapter for external tools
│       └── prompts/
│           ├── __init__.py
│           └── templates.py      # Prompt templates per node
├── tests/
│   ├── test_graph.py
│   └── test_nodes.py
├── langgraph.json                # LangGraph Platform config
├── pyproject.toml
├── requirements.txt
├── .env
└── README.md
```

### Key Decisions (Party Mode Recommendations)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Use LangGraph Platform API | Yes | No custom FastAPI wrapper needed |
| Timeout ownership | Elixir | LangGraph runs until canceled or complete |
| Context passing | REST payload | Elixir sends session output when requesting intervention |
| Python version | 3.11 | Stable, good async support |
| Checkpointer | SqliteSaver | MVP simplicity, upgrade to Postgres later |
| State model | TypedDict | Explicit, type-safe |
| Deployment | Docker container | Isolation, easy restart |

### langgraph.json Configuration

```json
{
  "$schema": "https://langgra.ph/schema.json",
  "graphs": {
    "babysitter-workflow": "./src/babysitter_agent/graph.py:workflow"
  },
  "dependencies": ["."],
  "env": ".env",
  "python_version": "3.11",
  "store": {
    "index": {
      "fields": ["session_id", "issue_id"]
    }
  }
}
```

### Key Dependencies

```
langgraph>=0.2.0
langchain>=0.3.0
langchain-openai>=0.2.0
langgraph-checkpoint-sqlite>=0.1.0
langchain-mcp-adapters>=0.1.0
```

### Initialization Commands

```bash
# Create directory structure
mkdir -p langgraph/src/babysitter_agent/{nodes,tools,prompts} langgraph/tests

# Install LangGraph CLI
pip install langgraph-cli

# Initialize project
cd langgraph
# Create files manually (custom structure, not template)
```

### API Contract: Elixir ↔ LangGraph

**Elixir calls LangGraph Platform REST API:**

| Endpoint | Purpose |
|----------|---------|
| `POST /threads` | Create new thread (maps to session) |
| `POST /threads/{id}/runs` | Start workflow execution |
| `GET /threads/{id}/runs/{run_id}/status` | Poll for status |
| `POST /threads/{id}/runs/{run_id}` | Resume after interrupt |
| `DELETE /threads/{id}/runs/{run_id}` | Cancel (timeout) |

**Context passed when requesting intervention:**
```json
{
  "session_id": "sess-abc123",
  "issue_id": "td-xyz789",
  "output_buffer": "...last 100KB of output...",
  "validation_results": [...],
  "retries": 2
}
```

**Note:** Project initialization using this structure should be the first implementation story for LangGraph integration.

---

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Already Made):**
- State authority: Elixir owns session state
- LangGraph role: Stateless workflow compute
- Communication: REST + polling

**Important Decisions (This Step):**
- Data storage locations
- Security boundaries
- Error handling patterns
- Infrastructure structure

**Deferred Decisions (Post-MVP):**
- PostgresSaver for LangGraph (upgrade from SQLite)
- mTLS between services (if remote deployment needed)
- Log aggregation with Loki
- Circuit breaker pattern for retries

### Data Architecture

| Decision | Choice | Rationale |
|----------|--------|-----------|
| LangGraph checkpointer | `./data/langgraph/checkpoints.db` | Project-relative, isolated from Elixir |
| Session→Thread mapping | Elixir Session + SQLite persistence | Durable, recoverable, decoupled from td |

**Session struct extension:**
```elixir
%Session{
  # ... existing fields ...
  langgraph_thread_id: String.t() | nil,
  langgraph_checkpoint_id: String.t() | nil,
}
```

**SQLite schema for session persistence (Party Mode addition):**
```elixir
# migration
create table(:session_langgraph_mappings, primary_key: false) do
  add :session_id, :string, primary_key: true
  add :thread_id, :string, null: false
  add :checkpoint_id, :string
  add :inserted_at, :utc_datetime
  add :updated_at, :utc_datetime
end
```

### Authentication & Security

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Elixir→LangGraph auth | None (localhost) | Single-user, network isolation |
| LangGraph binding | `127.0.0.1:8123` | No external exposure |

**Security model:** Trust boundary at localhost. LangGraph API not exposed externally.

### API & Communication Patterns

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Error handling | Retry 3x with exponential backoff, then escalate | Resilient to transient failures |
| Polling interval | 2 seconds | Balanced responsiveness |
| REST call timeout | 30 seconds | Allow for LLM inference time |
| Workflow timeout | None (Elixir cancels) | Elixir owns timeout authority |

**Retry configuration:**
```elixir
# Elixir retry config
@max_retries 3
@base_delay_ms 1000  # 1s, 2s, 4s
```

**Worst case retry time:** 7 seconds (1 + 2 + 4)
**Worst case with timeout:** ~37 seconds (7s retry + 30s timeout)

### Infrastructure & Deployment

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Compose structure | Single `docker-compose.yml` | Simple, all services together |
| Startup dependency | Elixir independent of LangGraph | Elixir handles LangGraph unavailability gracefully |
| Health check (Elixir) | `GET /health` | Existing pattern |
| Health check (LangGraph) | `GET /info` | Platform built-in |
| Log aggregation | Docker logs | Simplest, sufficient for MVP |

**docker-compose.yml (Party Mode Revised):**
```yaml
services:
  babysitter:
    build: ./elixir
    ports:
      - "4001:4001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    env_file: .env
    # NOTE: No depends_on for LangGraph - Elixir starts independently

  langgraph:
    build: ./langgraph
    ports:
      - "127.0.0.1:8123:8123"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123/info"]
      interval: 30s
      timeout: 10s
      retries: 3
    volumes:
      - ./data/langgraph:/app/data
    env_file: .env
```

**SQLite schema for session→thread mapping (Party Mode Addition):**
```elixir
# In Elixir, add migration for langgraph_sessions table
create table(:langgraph_sessions) do
  add :id, :uuid, primary_key: true
  add :session_id, :string, null: false
  add :thread_id, :string, null: false
  add :checkpoint_id, :string
  add :inserted_at, :utc_datetime
  add :updated_at, :utc_datetime
  
  create unique_index(:langgraph_sessions, [:session_id])
end
```

**Environment configuration:**
```bash
# .env
# Elixir/Phoenix
PHOENIX_PORT=4001
TD_DATABASE=.todos/issues.db

# LangGraph
LANGGRAPH_PORT=8123
LANGGRAPH_CHECKPOINT_DB=./data/langgraph/checkpoints.db

# LLM Providers
OPENAI_API_KEY=${OPENAI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

### Elixir LangGraph Client Module

```elixir
# lib/babysitter/langgraph/client.ex
defmodule Babysitter.LangGraphClient do
  use Tesla
  
  plug Tesla.Middleware.BaseUrl, "http://127.0.0.1:8123"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Timeout, timeout: 30_000
  
  @max_retries 3
  @base_delay_ms 1000
  
  def health_check do
    with_retry(fn -> get!("/info") end)
  end
  
  def create_thread do
    with_retry(fn -> post!("/threads", %{}) end)
  end
  
  def start_run(thread_id, input) do
    with_retry(fn -> post!("/threads/#{thread_id}/runs", %{input: input}) end)
  end
  
  def get_run_status(thread_id, run_id) do
    with_retry(fn -> get!("/threads/#{thread_id}/runs/#{run_id}/status") end)
  end
  
  def resume_run(thread_id, run_id, resume_value) do
    with_retry(fn -> 
      post!("/threads/#{thread_id}/runs/#{run_id}", %{command: %{resume: resume_value}})
    end)
  end
  
  def cancel_run(thread_id, run_id) do
    with_retry(fn -> delete!("/threads/#{thread_id}/runs/#{run_id}") end)
  end
  
  defp with_retry(fun, attempt \\ 1) do
    case fun.() do
      {:ok, response} -> {:ok, response}
      {:error, _reason} when attempt < @max_retries ->
        delay = @base_delay_ms * :math.pow(2, attempt - 1)
        Process.sleep(delay)
        with_retry(fun, attempt + 1)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Session Handling LangGraph Unavailability (Party Mode Addition)

```elixir
# In Session GenServer
def handle_call({:start_workflow, _}, _from, state) do
  case Babysitter.LangGraphClient.health_check() do
    {:ok, _} ->
      # LangGraph available, proceed with smart workflow
      case start_langgraph_workflow(state) do
        {:ok, new_state} -> {:reply, :ok, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    {:error, _} ->
      # LangGraph unavailable, use dumb intervention only
      {:reply, {:error, :langgraph_unavailable}, state}
  end
end
```

**Graceful degradation (Party Mode addition):**
```elixir
def handle_call({:start_workflow, _}, _from, state) do
  case LangGraphClient.health_check() do
    :ok -> # Proceed with LangGraph
    :error -> 
      # Fallback to dumb intervention only
      {:reply, {:error, :langgraph_unavailable}, state}
  end
end
```

### Infrastructure & Deployment

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Compose structure | Single `docker-compose.yml` | Simple, all services together |
| Health check (Elixir) | `GET /health` | Existing pattern |
| Health check (LangGraph) | `GET /info` | Platform built-in |
| Log aggregation | Docker logs | Simplest, sufficient for MVP |
| Startup dependency | None (Party Mode) | Elixir starts independently |

**docker-compose.yml structure:**
```yaml
services:
  babysitter:
    build: ./elixir
    ports:
      - "4001:4001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4001/health"]
    # NOTE: No depends_on - Elixir starts independently
    # and handles LangGraph unavailability gracefully
    env_file: .env
    volumes:
      - ./.todos:/app/.todos:ro
      - ./data/babysitter:/app/data

  langgraph:
    build: ./langgraph
    ports:
      - "127.0.0.1:8123:8123"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123/info"]
    volumes:
      - ./data/langgraph:/app/data
    env_file: .env
```

**Environment configuration:**
```bash
# .env
# Elixir/Phoenix
PHOENIX_PORT=4001
TD_DATABASE=.todos/issues.db

# LangGraph
LANGGRAPH_PORT=8123
LANGGRAPH_CHECKPOINT_DB=./data/langgraph/checkpoints.db

# LLM Providers
OPENAI_API_KEY=${OPENAI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

### Testing Support (Party Mode Addition)

**LangGraph test endpoints:**
```python
# For integration testing only - not exposed in production
@app.get("/test/simulate_failure")
def simulate_failure(duration_seconds: int = 5):
    """Simulate service unavailability for testing retry logic."""
    # Implementation for testing
    pass

@app.get("/test/simulate_slow")
def simulate_slow(duration_seconds: int = 10):
    """Simulate slow response for testing timeout logic."""
    pass
```

### Decision Impact Analysis

**Implementation Sequence:**
1. Create LangGraph project structure
2. Implement LangGraph workflow graph
3. Add Elixir LangGraph client module
4. Create SQLite migration for session→thread mapping
5. Extend Session struct with thread mapping
6. Create docker-compose.yml
7. Add health check endpoints
8. Add test failure simulation endpoints
9. Integration testing

**Cross-Component Dependencies:**
- Elixir needs LangGraph client before smart intervention works
- LangGraph needs checkpoint DB volume before state persistence works
- Docker Compose needs both services built before orchestration
- Session migration needed before thread mapping works

**Failure Modes & Recovery:**
| Failure | Detection | Recovery |
|---------|-----------|----------|
| LangGraph down | Health check fails | Dumb intervention only |
| LangGraph crash mid-workflow | Poll returns error | Elixir recreates thread from checkpoint |
| Elixir crash | OTP supervision | Restart, reconnect to LangGraph threads |
| Checkpoint DB corrupt | SqliteSaver error | Start fresh thread, log warning |

---

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

**Critical Conflict Points Identified:** 6 areas where AI agents could make different choices across Elixir/Go/Python boundaries.

### Naming Patterns

**JSON Field Naming:**
- **Convention:** `snake_case` everywhere
- **Applies to:** All JSON APIs, event payloads, config files
- **Elixir:** Default JSON encoding
- **Python:** Default JSON encoding
- **Go:** Use struct tags: `` `json:"field_name"` ``

**Event/Message Naming (Party Mode Clarification):**
- **Phoenix Channels:** `resource:action` (e.g., `session:started`, `session:stage`)
- **Internal/LangGraph:** `resource.action` (e.g., `workflow.interrupted`, `run.completed`)
- **Rationale:** Different contexts - `:` for Phoenix Channel protocol, `.` for internal events

**ID Format (Party Mode Clarification):**
| Entity | Format | Example |
|--------|--------|---------|
| Session ID | `sess-` + 6 hex | `sess-abc123` |
| TD Issue ID | `td-` + 6 hex | `td-83e28a` |
| LangGraph Thread ID | Native format | `th_abc123xyz` |
| LangGraph Run ID | Native format | `run_def456uvw` |
| LangGraph Checkpoint ID | Native format | `cp_ghi789rst` |

**Note:** LangGraph IDs are internal, stored in mapping table, never exposed to users.

### Format Patterns

**API Response Format:**
```json
// Success
{
  "data": {"thread_id": "th-xyz", "status": "running"},
  "error": null
}

// Error
{
  "data": null,
  "error": {
    "code": "validation_error",
    "message": "Thread ID is required"
  }
}
```

**Note:** LangGraph Platform's built-in API uses HTTP status codes + direct body. Only custom endpoints use wrapped format.

**Date/Time Format:**
- **Convention:** ISO 8601 strings
- **Format:** `2026-02-24T15:30:00Z`
- **Timezone:** UTC (Z suffix)
- **Parsing:** Native in all languages (Elixir `DateTime`, Python `datetime`, Go `time.Time`)

**Error Codes:**
| Code | Meaning |
|------|---------|
| `validation_error` | Input validation failed |
| `not_found` | Resource not found |
| `unauthorized` | Authentication failure |
| `rate_limited` | Too many requests |
| `langgraph_error` | LangGraph service error |
| `internal_error` | Unexpected server error |

**Error Code Constants (Party Mode Addition):**
```elixir
# Elixir - lib/babysitter/error_codes.ex
defmodule Babysitter.ErrorCodes do
  @validation_error "validation_error"
  @not_found "not_found"
  @unauthorized "unauthorized"
  @rate_limited "rate_limited"
  @langgraph_error "langgraph_error"
  @internal_error "internal_error"
  
  def validation_error, do: @validation_error
  def not_found, do: @not_found
  # ... etc
end
```

```python
# Python - src/babysitter_agent/error_codes.py
class ErrorCodes:
    VALIDATION_ERROR = "validation_error"
    NOT_FOUND = "not_found"
    UNAUTHORIZED = "unauthorized"
    RATE_LIMITED = "rate_limited"
    LANGGRAPH_ERROR = "langgraph_error"
    INTERNAL_ERROR = "internal_error"
```

```go
// Go - internal/errorcodes/codes.go
package errorcodes

const (
    ValidationError = "validation_error"
    NotFound        = "not_found"
    Unauthorized    = "unauthorized"
    RateLimited     = "rate_limited"
    LangGraphError  = "langgraph_error"
    InternalError   = "internal_error"
)
```

### State Mapping (Party Mode Addition)

**LangGraph ↔ Elixir Session State:**

| LangGraph Status | Elixir Session State | Trigger |
|------------------|---------------------|---------|
| `pending` | `initializing` | Thread created, run not started |
| `running` | `running` | Workflow executing |
| `interrupted` | `paused` | `interrupt()` called |
| `completed` | `completed` | Workflow finished successfully |
| `error` | `failed` | Workflow threw exception |
| `cancelled` | `stopped` | Elixir called cancel |

**State synchronization code:**
```elixir
defp map_langgraph_status("pending"), do: :initializing
defp map_langgraph_status("running"), do: :running
defp map_langgraph_status("interrupted"), do: :paused
defp map_langgraph_status("completed"), do: :completed
defp map_langgraph_status("error"), do: :failed
defp map_langgraph_status("cancelled"), do: :stopped
defp map_langgraph_status(_), do: :unknown
```

### Communication Patterns

**Phoenix Channels (Elixir↔Go TUI):**
- Topic format: `session:<id>`
- Event format: `resource:action`
- Heartbeat: Phoenix protocol built-in

**REST API (Elixir↔LangGraph):**
- Base URL: `http://127.0.0.1:8123`
- Content-Type: `application/json`
- Timeout: 30 seconds
- Retry: 3x with exponential backoff

### Cross-Language Examples

**Go struct with snake_case JSON:**
```go
type SessionStatus struct {
    SessionID   string `json:"session_id"`
    ThreadID    string `json:"thread_id"`
    Status      string `json:"status"`
    StartedAt   string `json:"started_at"` // ISO 8601
}
```

**Elixir response encoding:**
```elixir
%{
  data: %{session_id: session.id, status: session.status},
  error: nil
}
|> Jason.encode!()
```

**Python LangGraph state (TypedDict):**
```python
class WorkflowState(TypedDict):
    session_id: str
    issue_id: str
    output_buffer: str
    started_at: str  # ISO 8601
```

### Enforcement Guidelines

**All AI Agents MUST:**
1. Use `snake_case` for all JSON field names
2. Use `resource:action` for Phoenix Channel events, `resource.action` for internal
3. Use ISO 8601 strings for all timestamps
4. Use string error codes from `ErrorCodes` constants (no typos)
5. Use short random IDs with prefixes for our entities (`sess-`, `td-`)
6. Map LangGraph status to Elixir session state using the defined mapping

**Pattern Enforcement:**
- Elixir: `mix format` + code review
- Go: `go vet` + struct tag review
- Python: Type hints + linting

### Anti-Patterns to Avoid

❌ **Don't use camelCase in JSON:**
```json
{"sessionId": "..."}  // Wrong
{"session_id": "..."} // Correct
```

❌ **Don't use Unix timestamps:**
```json
{"started_at": 1708795800}  // Wrong
{"started_at": "2026-02-24T15:30:00Z"} // Correct
```

❌ **Don't mix event naming scopes:**
```
session.started     // Wrong for Phoenix Channels
session:started     // Correct for Phoenix Channels
workflow.interrupted // Correct for internal events
```

❌ **Don't hardcode error strings:**
```elixir
{:error, "validation_errror"}  // Wrong (typo)
{:error, ErrorCodes.validation_error()} // Correct
```

---

## Project Structure & Boundaries

### Complete Project Directory Structure (Party Mode Revised)

```
babysitter/
├── README.md
├── docker-compose.yml
├── .env                              # Single env file for all services (MVP)
├── .env.example                      # Template with all required vars
├── .gitignore                        # Includes data/, .env, _bmad-output/
├── AGENTS.md
│
├── docs/
│   ├── prd-babysitter-2026-02-13.md
│   ├── product-brief-agent_monitor-2026-02-03.md
│   ├── api-reference.md
│   ├── workflow-guide.md
│   └── troubleshooting.md
│
├── .babysitter/
│   └── workflows/
│       ├── default.yaml
│       ├── bugfix.yaml
│       └── feature.yaml
│
├── .todos/
│   └── issues.db                     # td SQLite database
│
├── data/                             # Runtime data (in .gitignore)
│   ├── babysitter/                   # Elixir session persistence
│   └── langgraph/                    # LangGraph checkpointer
│       └── checkpoints.db
│
├── elixir/                           # Elixir/Phoenix daemon
│   ├── Dockerfile                    # Party Mode addition
│   ├── mix.exs
│   ├── mix.lock
│   ├── .formatter.exs
│   ├── .gitignore
│   ├── README.md
│   ├── config/
│   │   ├── config.exs
│   │   ├── dev.exs
│   │   ├── prod.exs
│   │   ├── runtime.exs
│   │   └── test.exs
│   ├── lib/
│   │   ├── babysitter/
│   │   │   ├── application.ex
│   │   │   ├── babysitter.ex
│   │   │   │
│   │   │   ├── api/                 # Phoenix controllers
│   │   │   │   ├── session_controller.ex
│   │   │   │   ├── workflow_controller.ex
│   │   │   │   └── health_controller.ex
│   │   │   │
│   │   │   ├── channels/            # Phoenix Channels
│   │   │   │   ├── session_channel.ex
│   │   │   │   └── user_socket.ex
│   │   │   │
│   │   │   ├── session/             # Session management
│   │   │   │   ├── manager.ex       # SessionManager GenServer
│   │   │   │   ├── process.ex       # Per-session GenServer
│   │   │   │   ├── state_machine.ex
│   │   │   │   ├── output_parser.ex
│   │   │   │   └── supervisor.ex
│   │   │   │
│   │   │   ├── workflow/            # Workflow engine
│   │   │   │   ├── engine.ex
│   │   │   │   ├── stage.ex
│   │   │   │   ├── parser.ex        # YAML parser
│   │   │   │   ├── validator.ex
│   │   │   │   └── supervisor.ex
│   │   │   │
│   │   │   ├── intervention/        # Intervention engine
│   │   │   │   ├── dumb.ex          # Rules-based
│   │   │   │   ├── engine.ex
│   │   │   │   └── supervisor.ex
│   │   │   │
│   │   │   ├── langgraph/           # LangGraph integration (NEW)
│   │   │   │   ├── client.ex        # REST client
│   │   │   │   ├── mapper.ex        # State mapping
│   │   │   │   └── supervisor.ex
│   │   │   │
│   │   │   ├── td/                  # TD integration
│   │   │   │   ├── client.ex        # SQLite reader
│   │   │   │   └── context.ex       # Issue context extraction
│   │   │   │
│   │   │   ├── tmux/                # tmux integration
│   │   │   │   └── session.ex
│   │   │   │
│   │   │   ├── git/                 # Git integration
│   │   │   │   ├── commit.ex
│   │   │   │   └── pr.ex
│   │   │   │
│   │   │   ├── repo.ex              # Ecto repo
│   │   │   ├── error_codes.ex       # Error code constants
│   │   │   └── broadcast.ex         # Phoenix Channel broadcast helper
│   │   │
│   │   ├── babysitter_web/
│   │   │   ├── endpoint.ex
│   │   │   ├── router.ex
│   │   │   └── telemetry.ex
│   │   │
│   │   └── babysitter.ex
│   │
│   ├── priv/
│   │   ├── babysitter-tui           # Compiled Go binary
│   │   └── repo/
│   │       └── migrations/
│   │           └── 20260224120000_create_langgraph_sessions.exs  # Party Mode
│   │
│   └── test/
│       ├── test_helper.exs
│       ├── babysitter/
│       │   ├── session_test.exs
│       │   ├── workflow_test.exs
│       │   ├── langgraph_client_test.exs
│       │   └── intervention_test.exs
│       ├── e2e/                     # Party Mode addition
│       │   ├── session_workflow_test.exs
│       │   └── langgraph_integration_test.exs
│       └── support/
│           ├── fixtures.ex
│           └── mocks.ex
│
├── go/                              # Go TUI
│   ├── Dockerfile.dev               # For development (optional)
│   ├── go.mod
│   ├── go.sum
│   ├── .gitignore
│   ├── README.md
│   │
│   ├── cmd/
│   │   └── babysitter-tui/
│   │       └── main.go
│   │
│   ├── internal/
│   │   ├── client/                  # HTTP/WebSocket client
│   │   │   ├── client.go
│   │   │   ├── client_test.go       # Party Mode addition
│   │   │   ├── websocket.go
│   │   │   ├── websocket_test.go    # Party Mode addition
│   │   │   ├── phoenix.go           # Phoenix Channels protocol
│   │   │   ├── phoenix_test.go      # Party Mode addition
│   │   │   ├── retry.go
│   │   │   └── retry_test.go        # Party Mode addition
│   │   │
│   │   ├── tui/                     # Bubble Tea TUI
│   │   │   ├── app.go
│   │   │   ├── app_test.go          # Party Mode addition
│   │   │   ├── sessions.go
│   │   │   ├── sessions_test.go     # Party Mode addition
│   │   │   ├── output.go
│   │   │   ├── controls.go
│   │   │   └── styles.go
│   │   │
│   │   ├── models/
│   │   │   ├── session.go
│   │   │   ├── session_test.go      # Party Mode addition
│   │   │   ├── workflow.go
│   │   │   ├── workflow_test.go     # Party Mode addition
│   │   │   ├── error.go
│   │   │   └── error_test.go        # Party Mode addition
│   │   │
│   │   └── errorcodes/
│   │       ├── codes.go
│   │       └── codes_test.go        # Party Mode addition
│   │
│   └── pkg/
│       └── plugin/                  # Sidecar plugin exports (future)
│           └── plugin.go
│
├── langgraph/                       # LangGraph Python service (NEW)
│   ├── Dockerfile                   # Party Mode addition
│   ├── pyproject.toml
│   ├── requirements.txt
│   ├── .python-version
│   ├── langgraph.json
│   ├── .gitignore
│   ├── README.md
│   │
│   ├── src/
│   │   └── babysitter_agent/
│   │       ├── __init__.py
│   │       ├── graph.py             # Main workflow graph
│   │       ├── state.py             # TypedDict state definitions
│   │       ├── checkpointer.py      # SqliteSaver config
│   │       ├── error_codes.py       # Error code constants
│   │       │
│   │       ├── nodes/
│   │       │   ├── __init__.py
│   │       │   ├── plan.py          # Planning node
│   │       │   ├── execute.py       # Execution node
│   │       │   ├── validate.py      # Validation node
│   │       │   ├── review.py        # Review node
│   │       │   └── intervene.py     # Smart intervention node
│   │       │
│   │       ├── tools/
│   │       │   ├── __init__.py
│   │       │   └── mcp_tools.py     # MCP adapter tools
│   │       │
│   │       └── prompts/
│   │           ├── __init__.py
│   │           └── templates.py     # Prompt templates
│   │
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       ├── test_graph.py
│       ├── test_nodes/
│       │   ├── __init__.py
│       │   ├── test_plan.py
│       │   ├── test_execute.py
│       │   └── test_intervene.py
│       └── fixtures/
│           └── sample_outputs.py
│
├── _bmad/                           # BMAD methodology files
│   ├── bmm/
│   ├── core/
│   └── _config/
│
└── _bmad-output/                    # BMAD output artifacts
    ├── project-context.md
    └── planning-artifacts/
        ├── research/
        │   └── technical-langgraph-integration-research-2026-02-24.md
        └── architecture.md
```

### Architectural Boundaries

**Service Boundaries:**

| Service | Port | Responsibility | Dependencies |
|---------|------|----------------|--------------|
| Elixir/Phoenix | 4001 | Session management, API gateway, dumb intervention | tmux, td SQLite |
| LangGraph | 8123 | Workflow execution, smart intervention, checkpointing | LLM APIs |
| Go TUI | N/A (client) | User interface, real-time display | Elixir WebSocket |

**API Boundaries:**

| Boundary | Protocol | Auth |
|----------|----------|------|
| TUI ↔ Elixir | WebSocket (Phoenix Channels) | None (localhost) |
| Elixir ↔ LangGraph | REST (HTTP) | None (localhost) |
| Elixir ↔ td | SQLite (file read) | File system |
| Elixir ↔ tmux | CLI commands | Process |

**Data Boundaries:**

| Data Store | Owner | Location |
|------------|-------|----------|
| td issues.db | td CLI | `.todos/issues.db` |
| Session persistence | Elixir | `data/babysitter/` |
| LangGraph checkpoints | LangGraph | `data/langgraph/checkpoints.db` |

### Requirements to Structure Mapping

**Functional Requirements → Files:**

| FR | Location |
|----|----------|
| FR-1: Workflow definition | `elixir/lib/babysitter/workflow/`, `.babysitter/workflows/` |
| FR-2: Session lifecycle | `elixir/lib/babysitter/session/` |
| FR-3: Output capture | `elixir/lib/babysitter/session/output_parser.ex` |
| FR-4: Intervention engine | `elixir/lib/babysitter/intervention/`, `langgraph/src/babysitter_agent/nodes/intervene.py` |
| FR-5: TD integration | `elixir/lib/babysitter/td/` |
| FR-6: Git integration | `elixir/lib/babysitter/git/` |
| FR-7: Validation stages | `elixir/lib/babysitter/workflow/validator.ex`, `langgraph/src/babysitter_agent/nodes/validate.py` |
| FR-8: Real-time TUI | `go/internal/tui/`, `elixir/lib/babysitter/channels/` |
| FR-9: Human-in-the-loop | `langgraph/src/babysitter_agent/graph.py` (interrupt/resume) |
| FR-10: State persistence | `elixir/priv/repo/migrations/`, `data/` |

**Cross-Cutting Concerns → Files:**

| Concern | Location |
|---------|----------|
| Error codes | `elixir/lib/babysitter/error_codes.ex`, `go/internal/errorcodes/`, `langgraph/src/babysitter_agent/error_codes.py` |
| State mapping | `elixir/lib/babysitter/langgraph/mapper.ex` |
| Configuration | `.env`, `docker-compose.yml`, `langgraph/langgraph.json` |

### Integration Points

**Internal Communication:**

```
Go TUI ──WebSocket──▶ Elixir ──REST──▶ LangGraph
   │                     │                   │
   │ Phoenix Channels    │ HTTP + Polling    │
   │ (session:<id>)      │ (2s interval)     │
   │                     │                   │
   └─────────────────────┴───────────────────┘
```

**External Integrations:**

| Integration | Type | Location |
|-------------|------|----------|
| td CLI | SQLite read | `elixir/lib/babysitter/td/client.ex` |
| tmux | CLI commands | `elixir/lib/babysitter/tmux/session.ex` |
| git | CLI commands | `elixir/lib/babysitter/git/` |
| LLM APIs | HTTP | `langgraph/` (via langchain) |

### File Organization Patterns

**Configuration Files:**
- Root: `.env`, `docker-compose.yml`, `.gitignore`
- Per-service: `mix.exs`, `go.mod`, `pyproject.toml`
- LangGraph: `langgraph.json`

**Test Organization:**
- Elixir: `test/` directory, mirrors `lib/` structure
- Go: `*_test.go` co-located with source files
- Python: `tests/` directory
- E2E: `elixir/test/e2e/` for cross-service tests

**Runtime Data:**
- `data/` directory (in `.gitignore`)
- Created at first run
- Persistent across restarts

### Development Workflow

**Starting services:**
```bash
# Start all services
docker-compose up -d

# Or individually:
cd elixir && mix phx.server
cd langgraph && langgraph up
cd go && go run ./cmd/babysitter-tui
```

**Running tests:**
```bash
# Elixir
cd elixir && mix test

# Go
cd go && go test ./...

# Python
cd langgraph && pytest

# E2E
cd elixir && mix test test/e2e/
```

---

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:** All decisions work together. The fault isolation priority drives consistent choices: Elixir as state authority, LangGraph as stateless compute, REST+polling for simplicity.

**Pattern Consistency:** All three languages (Elixir, Go, Python) share consistent patterns for JSON naming, error codes, event naming, and date formats.

**Structure Alignment:** Project structure supports all architectural decisions with clear boundaries between services.

### Requirements Coverage Validation ✅

**Functional Requirements:** All 10 FRs have architectural support with specific file locations mapped.

**Non-Functional Requirements:** All 5 NFRs addressed through OTP supervision, tmux sessions, SQLite persistence, and fault isolation patterns.

### Implementation Readiness Validation ✅

**Decision Completeness:** All critical decisions documented with technology versions (Elixir 1.19, Go 1.25.5, Python 3.11, LangGraph 0.2.0+).

**Structure Completeness:** Complete directory tree with Dockerfiles, test structure, and E2E test directory.

**Pattern Completeness:** Error codes, state mapping, event naming, and cross-language examples all provided.

### Gap Analysis Results

**No Critical Gaps Found**

**Important (Non-Blocking):**
1. Dockerfile contents - to be defined in implementation story
2. LLM provider config - documented in `.env.example`
3. Test fixtures - to be added (Party Mode)

### Validation Issues Addressed (Party Mode Additions)

**1. Correlation ID Pattern (Nice-to-Have)**

For cross-service observability and debugging:

```elixir
# Elixir generates correlation ID
def generate_correlation_id do
  :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end

# Passed to LangGraph via header
def create_thread(correlation_id) do
  Tesla.Env.put_header(req, "x-correlation-id", correlation_id)
  post!("/threads", %{})
end
```

```python
# LangGraph receives correlation ID
@app.middleware("http")
async def add_correlation_id(request, call_next):
    correlation_id = request.headers.get("x-correlation-id", "unknown")
    # Log with correlation_id
    logger.info(f"[{correlation_id}] Processing request")
    response = await call_next(request)
    return response
```

**2. Revised Implementation Order**

More incremental approach, verify each piece:

1. Create LangGraph project structure
2. Create docker-compose.yml (LangGraph only)
3. Test LangGraph health endpoint (`curl http://localhost:8123/info`)
4. Add Elixir LangGraph client module
5. Create SQLite migration for session→thread mapping
6. Add Elixir to docker-compose.yml
7. Full integration testing

**3. Elixir Test Fixtures (Party Mode Addition)**

Add to existing test structure:
```
elixir/test/support/fixtures/
├── session_fixtures.ex      # Sample sessions
├── workflow_fixtures.ex     # Sample workflows
└── langgraph_fixtures.ex    # Mock LangGraph responses
```

```elixir
# elixir/test/support/fixtures/langgraph_fixtures.ex
defmodule Babysitter.LangGraphFixtures do
  def thread_fixture(attrs \\ %{}) do
    %{
      thread_id: "th_test_#{:rand.uniform(999_999)}",
      checkpoint_id: "cp_test_#{:rand.uniform(999_999)}",
      status: "pending"
    }
    |> Map.merge(attrs)
  end

  def run_status_fixture(status \\ "running") do
    %{
      status: status,
      thread_id: "th_test_123",
      run_id: "run_test_456"
    }
  end
end
```

**4. Feature Flag for LangGraph (Party Mode Addition)**

Enable/disable LangGraph without code changes:

```elixir
# config/config.exs
config :babysitter,
  langgraph_enabled: true

# lib/babysitter/session/process.ex
defp start_langgraph_workflow(state) do
  if Application.get_env(:babysitter, :langgraph_enabled) do
    # Use LangGraph for smart intervention
    do_start_langgraph(state)
  else
    # Fallback to dumb intervention only
    {:error, :langgraph_disabled}
  end
end
```

Set via environment:
```bash
# .env
LANGGRAPH_ENABLED=true  # or false to disable
```

### Architecture Completeness Checklist

**✅ Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**✅ Architectural Decisions**
- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**✅ Implementation Patterns**
- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**✅ Project Structure**
- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** ✅ READY FOR IMPLEMENTATION

**Confidence Level:** HIGH

**Key Strengths:**
1. Clear fault isolation boundaries
2. Consistent patterns across all three languages
3. All requirements mapped to specific files
4. State authority unambiguously defined (Elixir)
5. Graceful degradation when LangGraph unavailable
6. Feature flag for safe rollback (Party Mode)

**Areas for Future Enhancement:**
1. PostgresSaver for production scaling
2. Circuit breaker pattern for retries
3. API documentation generation
4. Monitoring/metrics integration

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented
- Use implementation patterns consistently across all components
- Respect project structure and boundaries
- Use correlation IDs for cross-service debugging
- Use feature flag for LangGraph rollback if needed

**First Implementation Priority:**
1. Create LangGraph project structure (`langgraph/` directory)
2. Create docker-compose.yml (LangGraph only first)
3. Test LangGraph health endpoint
4. Add Elixir LangGraph client module
5. Create SQLite migration for session→thread mapping
6. Add Elixir to docker-compose.yml
7. Integration testing
