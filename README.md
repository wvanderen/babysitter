# Babysitter

A workflow orchestration daemon for AI-assisted development. Babysitter manages agent sessions through configurable workflows, with support for validation, retries, escalation, and real-time monitoring.

## Architecture

- **Daemon** (Elixir/Phoenix): REST API + WebSocket server for session management
- **TUI** (Go): Terminal user interface for monitoring and control
- **Workflows** (YAML): Declarative workflow definitions with stages, validations, and transitions

## Quick Start

### Prerequisites

- Elixir 1.19+
- Go 1.21+
- SQLite3
- tmux

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd babysitter

# Install Elixir dependencies
mix deps.get

# Install Go dependencies
cd go && go mod download && cd ..

# Build the TUI
cd go && go build -o ../priv/babysitter-tui ./cmd/babysitter-tui && cd ..
```

### Running the Daemon

```bash
# Start the daemon (default port 4000)
mix phx.server

# Or with custom configuration
PORT=4002 mix phx.server
```

### Using the TUI

```bash
# Connect to daemon (default http://localhost:4000)
./priv/babysitter-tui

# With custom API URL
./priv/babysitter-tui -api http://localhost:4002

# Auto-connect and select session
./priv/babysitter-tui -connect -session <session-id>
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | Daemon HTTP port |
| `DATABASE_PATH` | `babysitter.db` | SQLite database path |

## API Reference

### Health Endpoints

```
GET /api/health   # Health check
GET /api/ready    # Readiness check
GET /api/status   # System status
```

### Session Management

```
GET    /api/sessions           # List all sessions
POST   /api/sessions           # Create new session
GET    /api/sessions/:id       # Get session details
DELETE /api/sessions/:id       # Stop and delete session
POST   /api/sessions/:id/pause   # Pause session
POST   /api/sessions/:id/resume  # Resume session
POST   /api/sessions/:id/intervene # Intervention (retry/restart/escalate/skip)
```

### Workflow Management

```
GET    /api/workflows          # List available workflows
GET    /api/workflows/:id      # Get workflow definition
POST   /api/workflows          # Create workflow
POST   /api/workflows/:id/execute # Execute workflow
```

### WebSocket

Connect to `/ws` for real-time session updates.

## Workflows

Workflows are defined in `.babysitter/workflows/*.yaml` files.

### Workflow Structure

```yaml
id: my-workflow
name: My Workflow
description: Workflow description
intelligence: hybrid  # dumb | smart | hybrid

entry_point: stage-one

stages:
  - id: stage-one
    type: action      # agent | action | validation | decision
    command: "echo 'Hello'"
    timeout: 5m
    on_success: stage-two
    on_failure: escalate

  - id: stage-two
    type: agent
    prompt_template: |
      Implement feature {{feature.name}}
    timeout: 30m
    validation:
      - type: compile
      - type: tests
    on_success: complete
    on_failure: retry
```

### Stage Types

| Type | Description |
|------|-------------|
| `action` | Execute a shell command |
| `agent` | Run AI agent with prompt |
| `validation` | Run validation checks |
| `decision` | Branch based on conditions |

### Validation Types

| Type | Description |
|------|-------------|
| `compile` | Check compilation succeeds |
| `tests` | Run test suite |
| `lint` | Run linter |
| `command` | Execute custom command |
| `output_contains` | Check output contains pattern |
| `output_matches` | Check output matches regex |
| `exit_code` | Check command exit code |

### Timeout Format

Timeouts can be specified as:
- Integer milliseconds: `30000`
- Seconds: `30s`
- Minutes: `5m`
- Hours: `1h`
- Infinite: `infinity`

## Session States

```
initializing → running → completed
                ↓
              paused → running
                ↓
              escalated
                ↓
              stopped
```

| State | Description |
|-------|-------------|
| `initializing` | Session being created |
| `running` | Active session |
| `paused` | Paused session |
| `completed` | Successfully finished |
| `failed` | Failed with error |
| `escalated` | Requires human attention |
| `stopped` | Terminated |

## Interventions

When a session is in a problematic state, you can intervene:

| Action | Description |
|--------|-------------|
| `retry` | Retry the current stage |
| `restart` | Restart from the beginning |
| `escalate` | Mark for human review |
| `skip` | Skip current stage |

## TUI Controls

| Key | Action |
|-----|--------|
| `?` | Show help |
| `q` | Quit |
| `j/k` | Navigate list |
| `enter` | Select |
| `p` | Pause/Resume |
| `r` | Refresh |

### TUI Command Line Options

```
-api string        Daemon API URL (default "http://localhost:4000")
-ws string         WebSocket URL (defaults to ws://<api-host>/ws)
-session string    Session ID to select on start
-connect           Auto-connect to WebSocket
-version           Show version
-no-alt-screen     Disable alternate screen buffer
```

## Development

### Running Tests

```bash
# Elixir tests
mix test

# Go tests
cd go && go test ./...
```

### Project Structure

```
babysitter/
├── lib/
│   ├── babysitter/           # Core business logic
│   │   ├── session.ex        # Session GenServer
│   │   ├── workflow/         # Workflow parsing
│   │   ├── td/               # td CLI integration
│   │   └── validation.ex     # Validation runner
│   └── babysitter_web/       # Phoenix web layer
│       ├── controllers/      # REST controllers
│       └── channels/         # WebSocket channels
├── go/
│   ├── cmd/babysitter-tui/   # TUI entrypoint
│   └── internal/             # Go internals
├── .babysitter/
│   └── workflows/            # Workflow definitions
└── priv/
    └── babysitter-tui        # Compiled TUI binary
```

## License

MIT
