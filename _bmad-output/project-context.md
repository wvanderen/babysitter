---
project_name: babysitter
user_name: Lem
date: 2026-02-24
sections_completed:
  - technology_stack
  - language_rules
  - framework_rules
  - testing_rules
  - quality_rules
  - workflow_rules
  - anti_patterns
status: complete
rule_count: 35
optimized_for_llm: true
---

# Project Context for AI Agents

_Critical rules and patterns for AI agents implementing code in this project. Focus on unobvious details._

---

## Technology Stack & Versions

### Backend (Elixir)
- **Elixir**: ~> 1.19 | **Phoenix**: ~> 1.7 | **Ecto SQLite3**: ~> 0.17
- **Jason**: ~> 1.4 | **Plug Cowboy**: ~> 2.7 | **Yamerl**: ~> 0.10

### TUI (Go)
- **Go**: 1.25.5 | **Bubble Tea**: v1.3.10 | **Bubbles**: v1.0.0
- **Lipgloss**: v1.1.0 | **Gorilla WebSocket**: v1.5.3

### External
- **tmux**: Required for session management | **SQLite3**: Database

---

## Critical Implementation Rules

### Elixir Rules

1. **GenServer Pattern**
   - Use Registry for process lookup: `{:via, Registry, {Babysitter.SessionRegistry, id}}`
   - Always implement `terminate/2` for tmux cleanup

2. **State Machine Transitions**
   - Define in `@valid_transitions %{}` module attribute
   - Validate before state changes
   - Return `{:error, {:invalid_transition, from, to}}` for invalid

3. **Type Specifications**
   - `@type` and `@spec` for public functions
   - `@derive {Jason.Encoder, only: [...]}` for JSON structs
   - `@enforce_keys` for required struct fields

4. **Testing**
   - `use ExUnit.Case, async: false` for GenServer tests
   - Unique IDs: `"test-#{:rand.uniform(1_000_000)}"`
   - Clean up sessions in teardown

### Go Rules

1. **Constructor Pattern**: `func New(baseURL string, opts ...ClientOption) *Client`
2. **Error Handling**: Custom types with `Error() string`, wrap with `fmt.Errorf("...: %w", err)`
3. **Testing**: `httptest.NewServer` for HTTP mocks, table-driven tests
4. **WebSocket**: Phoenix channel protocol - `{topic, event, payload, ref}`

### Phoenix Framework Rules

1. **Controllers**: `lib/babysitter_web/controllers/`, return conn with status
2. **Channels**: Join topics `"session:<id>"`, broadcast via `Babysitter.Broadcast`
3. **Router**: API under `/api`, WebSocket at `/socket`
4. **Supervision**: SessionSupervisor (DynamicSupervisor), Registry for discovery

### Testing Rules

1. **Elixir**: Mirror lib structure, `async: false` for GenServer, cleanup in teardown
2. **Go**: `httptest.NewServer`, table-driven tests, assert error types
3. **E2E**: `test/e2e/` for full workflow tests
4. **Commands**: `mix test` | `cd go && go test ./...`

### Code Quality & Style

1. **Elixir**: `mix format` before commit, `@moduledoc` for public modules
2. **Go**: Standard conventions, `go vet`
3. **Naming**: snake_case/PascalCase (Elixir), camelCase/PascalCase (Go)

### Development Workflow

1. **Build**: `mix deps.get` | `cd go && go mod download` | Build TUI: `cd go && go build -o ../priv/babysitter-tui ./cmd/babysitter-tui`
2. **Run**: `mix phx.server` | Custom port: `PORT=4002 mix phx.server`
3. **td CLI**: `td usage --new-session` at start | `td critical-path` for next work | Workflow: `start → log → handoff → review → approve`

### Critical Anti-Patterns

1. **NEVER**
   - Use `td close` for completed work - use `td review` → `td approve`
   - Skip `td handoff` before `td review`
   - Approve your own work (td enforces)
   - Forget tmux cleanup in `terminate/2`

2. **Session State Machine**
   - `initializing` → `running`, `stopped`, `failed`
   - `running` → `paused`, `completed`, `failed`, `escalated`, `stopped`
   - `paused` → `running`, `escalated`, `stopped`
   - `escalated` → `running`, `stopped`

3. **WebSocket Protocol**
   - Must join: `{"topic": "session:<id>", "event": "phx_join", ...}`
   - Heartbeat with ping to keep connection alive

4. **Buffer Management**
   - Max 100KB output buffer, older content truncated
   - Use `Session.clear_buffer/1` to reset

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code
- Follow ALL rules exactly as documented
- When in doubt, prefer the more restrictive option

**For Humans:**
- Keep lean and focused on agent needs
- Update when technology stack changes
- Review quarterly for outdated rules

Last Updated: 2026-02-24
