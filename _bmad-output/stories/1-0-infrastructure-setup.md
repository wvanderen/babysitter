# Story 1.0: Infrastructure Setup

Status: approved-with-followups

<!-- BMAD-TD Integration: This story is synced with td epic td-08b291 -->

## td Integration

- **td Epic**: `td-08b291`
- **td Tasks**: 4 issues (0 open, 0 in-progress, 0 blocked, 4 in_review)
- **Last Sync**: 2026-02-26T14:00:00Z
- **Sync Status**: approved-with-followups

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1: Create tmux verification module | `td-0ad925` | in_review |
| Task 2: Create directory structure on startup | `td-052a7a` | in_review |
| Task 3: Integrate setup into application startup | `td-97d825` | in_review |
| Task 4: Add unit tests for infrastructure setup | `td-2e1730` | in_review |

---

## Story

As a user,
I want tmux and required dependencies to be available,
So that agent sessions can run and be attachable for debugging.

## Acceptance Criteria

1. **AC1: tmux Verification**
   - Given a fresh environment
   - When babysitter starts
   - Then tmux is verified available
   - And error is clear if tmux is missing

2. **AC2: Directory Structure**
   - Required directories are created on startup
   - `data/babysitter/` for session persistence
   - `data/langgraph/` for LangGraph checkpoints
   - `.babysitter/workflows/` for workflow definitions

3. **AC3: Error Handling**
   - Clear error message if tmux is not installed
   - Guidance on how to install tmux
   - Non-zero exit code on missing dependency

## Tasks / Subtasks

- [x] Task 1: Create tmux verification module (AC: #1, #3) [td:td-0ad925]
  - [x] 1.1: Create `lib/babysitter/tmux/verifier.ex` module
  - [x] 1.2: Implement `verify_tmux_available/0` function
  - [x] 1.3: Return `{:ok, version}` or `{:error, :tmux_not_found}`
  - [x] 1.4: Add helpful error message with installation instructions

- [x] Task 2: Create directory structure on startup (AC: #2) [td:td-052a7a]
  - [x] 2.1: Create `lib/babysitter/setup.ex` module
  - [x] 2.2: Implement `ensure_directories/0` function
  - [x] 2.3: Create `data/babysitter/` if missing
  - [x] 2.4: Create `data/langgraph/` if missing
  - [x] 2.5: Create `.babysitter/workflows/` if missing

- [x] Task 3: Integrate setup into application startup (AC: #1, #2, #3) [td:td-97d825]
  - [x] 3.1: Add setup check to `application.ex` supervision tree
  - [x] 3.2: Fail fast if tmux not available
  - [x] 3.3: Log successful setup on startup

- [x] Task 4: Add unit tests (AC: #1, #2, #3) [td:td-2e1730]
  - [x] 4.1: Test tmux verification success path
  - [x] 4.2: Test tmux verification failure path (mock)
  - [x] 4.3: Test directory creation

## Dev Notes

### Architecture Context

From architecture.md:
- tmux is required for session attachability and process isolation (NFR-5)
- Fault isolation Layer 4: tmux/agents isolated per session
- Sessions survive daemon restarts via tmux

### Key Files to Create/Modify

```
elixir/
├── lib/
│   └── babysitter/
│       ├── application.ex        # Add setup task
│       ├── setup.ex              # NEW: Directory setup module
│       └── tmux/
│           └── verifier.ex       # NEW: tmux verification
└── test/
    └── babysitter/
        ├── setup_test.exs        # NEW
        └── tmux/
            └── verifier_test.exs # NEW
```

### Elixir Implementation Patterns

From project-context.md:
- Use `@spec` for public functions
- Use `@moduledoc` for public modules
- Run `mix format` before commit
- Tests: `use ExUnit.Case, async: false` for GenServer tests
- Unique IDs: `"test-#{:rand.uniform(1_000_000)}"`

### tmux Verification Logic

```elixir
defmodule Babysitter.Tmux.Verifier do
  @moduledoc "Verifies tmux availability and version"

  @spec verify_tmux_available() :: {:ok, String.t()} | {:error, :tmux_not_found}
  def verify_tmux_available do
    case System.cmd("tmux", ["-V"]) do
      {output, 0} ->
        version = parse_version(output)
        {:ok, version}
      {_error, _code} ->
        {:error, :tmux_not_found}
    end
  end

  defp parse_version(output) do
    output |> String.trim() |> String.replace("tmux ", "")
  end
end
```

### Directory Setup Logic

```elixir
defmodule Babysitter.Setup do
  @moduledoc "Ensures required directories exist"

  @required_dirs [
    "data/babysitter",
    "data/langgraph",
    ".babysitter/workflows"
  ]

  @spec ensure_directories() :: :ok | {:error, term()}
  def ensure_directories do
    Enum.each(@required_dirs, &File.mkdir_p/1)
    :ok
  end
end
```

### Testing Standards

- Unit tests for each module
- Mock tmux command for failure scenarios
- Use `on_exit` callback for cleanup

### Project Structure Notes

- Follows architecture.md directory structure exactly
- Creates runtime data directories in `.gitignore`
- Creates `.babysitter/` for workflow configuration

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Fault Isolation Layers]
- [Source: _bmad-output/planning-artifacts/architecture.md#Infrastructure & Deployment]
- [Source: _bmad-output/project-context.md#Elixir Rules]
- [Source: docs/prd-babysitter-2026-02-13.md#tmux Integration]

## Dev Agent Record

### Agent Model Used

Claude (GLM-5) - ses_18b3dc

### Debug Log References

None required - straightforward implementation

### Completion Notes List

**Task 2 (td-052a7a): Create directory structure on startup**
- Created `Babysitter.Setup` module with `required_dirs/0`, `ensure_directories/1`, and `ensure_directories!/0` functions
- Implemented using `File.mkdir_p/1` for idempotent directory creation
- Added comprehensive unit tests with proper cleanup via `on_exit` callbacks
- All 4 tests pass

**Task 3 (td-97d825): Integrate setup into application startup**
- Created `Babysitter.SetupWorker` GenServer for startup verification
- Added SetupWorker as first child in supervision tree
- Verifies tmux availability and logs version on startup
- Creates required directories via `Babysitter.Setup.ensure_directories!/0`
- Logs "Babysitter setup complete" on successful initialization
- Application fails to start if tmux is not available (fail-fast)
- Added unit tests for SetupWorker

**Task 4 (td-2e1730): Add unit tests for infrastructure setup**
- Tests implemented as part of Tasks 1-3 (co-located with implementation)
- tmux verification tests: success path, failure path (mock), installation instructions
- Setup module tests: required_dirs/0, ensure_directories/0 and /0!
- SetupWorker tests: start_link/1 and init/1 validation
- All 11 infrastructure tests pass with no regressions

### File List

| File | Action | Description |
|------|--------|-------------|
| `lib/babysitter/setup.ex` | NEW | Directory setup module |
| `test/babysitter/setup_test.exs` | NEW | Unit tests for setup module |
| `lib/babysitter/setup_worker.ex` | NEW | Startup verification GenServer |
| `test/babysitter/setup_worker_test.exs` | NEW | Unit tests for SetupWorker |
| `lib/babysitter/tmux/verifier.ex` | NEW | tmux verification module |
| `test/babysitter/tmux/verifier_test.exs` | NEW | Unit tests for tmux verification |
| `lib/babysitter/retry_handler.ex` | MODIFIED | Formatting changes during tmux implementation |
| `test/retry_handler_test.exs` | MODIFIED | Formatting changes during tmux implementation |
| `lib/babysitter/application.ex` | MODIFIED | Added SetupWorker to supervision tree |

---

## Senior Developer Review (AI)

**Date:** 2026-02-26
**Outcome:** approved-with-followups
**Action Items:** 5

### Summary
Epic-level code review completed. Story is functionally complete with all acceptance criteria met (AC1-AC3). All 11 tests pass, code is properly formatted, compiles without warnings. 5 minor quality improvements identified.

### Acceptance Criteria Validation
- AC1: tmux Verification - IMPLEMENTED ✓
- AC2: Directory Structure - IMPLEMENTED ✓
- AC3: Error Handling - IMPLEMENTED ✓

### Action Items
- [ ] [MEDIUM] Add negative test for SetupWorker tmux failure scenario [td:td-37d362]
- [ ] [MEDIUM] Fix test isolation in setup_test.exs ensure_directories! test [td:td-2b70c5]
- [ ] [MEDIUM] Update Story 1.0 File List to include retry_handler changes [td:td-a40132]
- [ ] [LOW] Fix test describe naming inconsistency in setup_test.exs [td:td-b6b18d]
- [ ] [LOW] Add edge case tests for parse_version function [td:td-a0c652]

---

| 2026-02-26T14:00:00Z | review-complete | Epic review completed - approved with 5 followup tasks |

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T00:00:00Z | initialized | Story created with td epic td-08b291 and 4 tasks |
| 2026-02-26T11:06Z | task-complete | td-052a7a: Create directory structure on startup |
| 2026-02-26T11:14Z | task-complete | td-97d825: Integrate setup into application startup |
| 2026-02-26T12:30Z | task-complete | td-2e1730: Add unit tests for infrastructure setup |
