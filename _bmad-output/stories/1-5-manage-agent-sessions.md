# Story 1.5: Manage Agent Sessions

Status: complete

<!-- BMAD-TD Integration: This story is synced with td task td-35998b -->

## td Integration

- **td Task**: `td-35998b`
- **td Epic**: Epic 1 (Foundation)
- **Last Sync**: 2026-02-26T16:30:00Z
- **Sync Status**: in_review

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1: Create tmux session for agents | `td-35998b` | in_review |

---

## Story

As a user,
I want agent sessions to be managed with tmux,
So that I can attach to sessions for debugging and sessions survive daemon restarts.

## Acceptance Criteria

1. **AC1: tmux Session Creation**
   - Given a session creation request
   - When the session is created
   - Then a tmux session is created with a unique name
   - And the session is in detached mode

2. **AC2: Output Capture**
   - Given a running agent session
   - When output is produced (stdout/stderr)
   - Then the output is captured via pipe-pane
   - And output is stored in a buffer

3. **AC3: Session Attachability**
   - Given a running agent session
   - When I want to debug
   - Then I can attach to the tmux session
   - And the session survives daemon restarts

## Tasks / Subtasks

- [x] Task 1: Create tmux session for agents (AC: #1, #2, #3) [td:td-35998b]
  - [x] 1.1: `Babysitter.Tmux` module for tmux integration
  - [x] 1.2: `Babysitter.Session` GenServer for session lifecycle
  - [x] 1.3: `Babysitter.OutputCapture` for real-time output capture
  - [x] 1.4: Session state machine (initializing → running → paused → completed/failed)
  - [x] 1.5: Session cleanup on terminate (tmux session killed)

## Dev Notes

### Architecture Context

From architecture.md:
- FR-2: Session lifecycle management (tmux-based agent processes)
- FR-3: Output capture and parsing (signal detection, error extraction)
- NFR-5: Attachability - tmux sessions for debugging

### Implementation Details

The session management is implemented across several modules:

1. **Babysitter.Tmux** (`lib/babysitter/tmux.ex`)
   - Low-level tmux integration
   - `create_session/2` - creates detached tmux session
   - `kill_session/1` - kills session
   - `capture_pane/2` - captures output
   - `pipe_pane/3` - sets up output capture to file
   - `send_keys/3` - sends commands to session

2. **Babysitter.Session** (`lib/babysitter/session.ex`)
   - GenServer for session lifecycle
   - State machine with valid transitions
   - Output buffer management
   - Validation result storage
   - Agent auto-start support

3. **Babysitter.OutputCapture** (`lib/babysitter/output_capture.ex`)
   - GenServer for real-time output capture
   - Uses pipe-pane for stdout/stderr capture
   - File-based pipe with async reader
   - Buffer management with max size
   - Subscriber broadcast for real-time updates

4. **Babysitter.Tmux.Verifier** (`lib/babysitter/tmux/verifier.ex`)
   - Verifies tmux availability at startup
   - Provides installation instructions

### Testing

All session-related tests pass:
- `test/session_test.exs` - Session lifecycle tests
- `test/session_manager_test.exs` - Manager tests
- `test/tmux_test.exs` - Tmux integration tests
- `test/output_capture_test.exs` - Output capture tests

Total: 53 tests, 0 failures

## Dev Agent Record

### Agent Model Used

Claude (GLM-5) - ses_56baeb

### Completion Notes

**Task 1 (td-35998b): Manage Agent Sessions**
- Verified existing implementation meets all acceptance criteria
- Fixed test isolation issue in git.ex (changed %ci to %aI for ISO8601 dates)
- Fixed workflow controller test to include required workflow fields
- All session-related tests pass (53 tests)

### File List

| File | Action | Description |
|------|--------|-------------|
| `lib/babysitter/git.ex` | MODIFIED | Fixed date format for recent_commits |
| `test/controllers/workflow_controller_test.exs` | MODIFIED | Added required workflow fields |

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T16:20:00Z | task-started | td-35998b: Story 1.5: Manage Agent Sessions |
| 2026-02-26T16:30:00Z | task-complete | td-35998b: Verified implementation, fixed tests |
