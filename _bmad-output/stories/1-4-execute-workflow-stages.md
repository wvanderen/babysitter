# Story 1.4: Execute Workflow Stages

Status: complete

<!-- BMAD-TD Integration: This story is synced with td epic td-daa260 -->

## td Integration

- **td Epic**: `td-daa260`
- **td Tasks**: 4 issues
- **Last Sync**: 2026-02-26T15:57:00Z
- **Sync Status**: complete

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1: WorkflowInstance GenServer | `td-5ea0f6` | **complete** |
| Task 2: StageExecutor implementation | `td-144e92` | **complete** |
| Task 3: TransitionEngine for stage progression | `td-135b03` | **complete** |
| Task 4: State machine and error handling | `td-6ea554` | **complete** |

---

## Story

As a user,
I want workflows to execute stage-by-stage following defined transitions,
So that work progresses automatically from planning to completion.

## Acceptance Criteria

1. **AC1: Stages Run in Order**
   - Given a validated workflow
   - When execution starts
   - Then stages run in order following transition rules
   - **Status**: ✅ Implemented - WorkflowInstance executes stages sequentially via `handle_info(:execute_current_stage, state)` and `spawn_stage_execution/1`

2. **AC2: On Success Moves to Next Stage**
   - Given a stage completes successfully
   - When the result is evaluated
   - Then on_success transition moves to the next stage
   - **Status**: ✅ Implemented - TransitionEngine.evaluate_shortcut/2 returns `{:ok, stage.on_success}` for success results; WorkflowInstance.handle_stage_result/2 triggers next stage

3. **AC3: On Failure Triggers Intervention or Retry**
   - Given a stage fails or times out
   - When the result is evaluated
   - Then on_failure triggers intervention or retry logic
   - **Status**: ✅ Implemented - TransitionEngine handles failure/timeout shortcuts; WorkflowInstance retries up to max_retries before failing

## Tasks / Subtasks

- [x] Task 1: WorkflowInstance GenServer (AC: #1, #2, #3) [td:td-5ea0f6]
  - [x] 1.1: Create `lib/babysitter/workflow_instance.ex` GenServer module
  - [x] 1.2: Implement state machine: pending → running → completed/failed/escalated/stopped
  - [x] 1.3: Implement `start/2`, `pause/1`, `resume/1`, `stop/1` lifecycle functions
  - [x] 1.4: Implement `handle_info(:execute_current_stage, state)` for stage execution
  - [x] 1.5: Track execution history with timing and metadata
  - [x] 1.6: Support variable interpolation for prompts

- [x] Task 2: StageExecutor implementation (AC: #1, #2) [td:td-144e92]
  - [x] 2.1: Create `lib/babysitter/stage_executor.ex` module
  - [x] 2.2: Implement `execute/3` for different stage types (action, agent, decision, validation)
  - [x] 2.3: Execute commands in tmux and capture output
  - [x] 2.4: Build Result struct with status, output, exit_code, timing
  - [x] 2.5: Run stage validations and update result status

- [x] Task 3: TransitionEngine for stage progression (AC: #2, #3) [td:td-135b03]
  - [x] 3.1: Create `lib/babysitter/transition_engine.ex` module
  - [x] 3.2: Implement `next_stage/2` to determine next stage from result
  - [x] 3.3: Support explicit transitions with conditions (success, failure, timeout, output_contains, exit_code)
  - [x] 3.4: Support shortcut transitions (on_success, on_failure, on_timeout)
  - [x] 3.5: Handle fallback chains (timeout → failure → success)

- [x] Task 4: State machine and error handling (AC: #1, #2, #3) [td:td-6ea554]
  - [x] 4.1: Define valid state transitions in `@valid_transitions` map
  - [x] 4.2: Validate transitions before state changes
  - [x] 4.3: Handle stage execution results (success, failure, timeout)
  - [x] 4.4: Implement retry logic with max_retries limit
  - [x] 4.5: Trigger intervention when no transition defined and retries exhausted

## Dev Notes

### Architecture Context

From architecture.md:
- FR-1: Workflow definition and execution - core functional requirement
- Workflow engine runs as GenServer in Elixir supervision tree
- Stages run in tmux for attachability and crash recovery
- State authority: Elixir owns session state

### Key Files (Already Implemented)

```
lib/babysitter/
├── workflow_instance.ex      # GenServer for workflow execution
├── stage_executor.ex         # Stage execution in tmux
├── transition_engine.ex      # Transition evaluation logic
├── transition.ex             # Transition struct definition
├── stage.ex                  # Stage struct definition
├── broadcast.ex              # Phoenix Channel broadcasts
└── state/
    └── persistence.ex        # State persistence for recovery

test/
├── workflow_instance_test.exs    # 23 tests
├── stage_executor_test.exs        # 31 tests
├── transition_engine_test.exs     # 26 tests
└── e2e/workflow_test.exs          # E2E tests
```

### Implementation Patterns

**State Machine Transitions** (from WorkflowInstance):
```elixir
@valid_transitions %{
  pending: [:running, :stopped],
  running: [:paused, :completed, :failed, :escalated, :stopped],
  paused: [:running, :escalated, :stopped],
  completed: [:stopped],
  failed: [:running, :stopped],
  escalated: [:running, :stopped]
}
```

**Stage Execution Flow**:
```
start() → handle_info(:execute_current_stage) → spawn_stage_execution()
  → StageExecutor.execute() → {:stage_execution_complete, result}
  → handle_stage_result() → TransitionEngine.next_stage()
  → next stage or complete/fail
```

**Transition Evaluation** (from TransitionEngine):
- Explicit transitions checked first (sorted by priority)
- Falls back to shortcut transitions (on_success/on_failure/on_timeout)
- Returns `{:ok, stage_id}`, `{:ok, :complete}`, or `{:error, :no_transition_defined}`

### Testing Standards

- Unit tests for WorkflowInstance, StageExecutor, TransitionEngine
- E2E tests for full workflow execution
- Tests use `async: false` for GenServer stateful tests
- Mock tmux sessions for isolation

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#FR-1]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.4]
- [Source: _bmad-output/project-context.md#GenServer Pattern]
- [Source: lib/babysitter/workflow_instance.ex]
- [Source: lib/babysitter/stage_executor.ex]
- [Source: lib/babysitter/transition_engine.ex]

---

## File List

| File | Status | Description |
|------|--------|-------------|
| `lib/babysitter/workflow_instance.ex` | EXISTS | WorkflowInstance GenServer with state machine |
| `lib/babysitter/stage_executor.ex` | EXISTS | Stage execution in tmux with Result struct |
| `lib/babysitter/transition_engine.ex` | EXISTS | Transition evaluation with conditions |
| `lib/babysitter/transition.ex` | EXISTS | Transition struct definition |
| `lib/babysitter/stage.ex` | EXISTS | Stage struct definition |
| `test/workflow_instance_test.exs` | EXISTS | 23 unit tests |
| `test/stage_executor_test.exs` | EXISTS | 31 unit tests |
| `test/transition_engine_test.exs` | EXISTS | 26 unit tests |
| `test/e2e/workflow_test.exs` | EXISTS | E2E workflow tests |

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T15:55:00Z | initialized | Story created with td epic td-daa260 and 4 tasks (code pre-existing) |
| 2026-02-26T15:57:00Z | approved | All 4 tasks approved by ses_2fc5b3 after review |

## Completion Notes

**Implementation Summary:**
- WorkflowInstance GenServer manages workflow execution lifecycle
- StageExecutor executes stages in tmux, captures output, runs validations
- TransitionEngine determines next stage based on execution results
- Full state machine with valid transitions and error handling
- 80 unit tests passing, E2E tests covering workflow execution

**Key Decisions:**
- Async stage execution via Task.start to avoid GenServer blocking
- Retry logic built into WorkflowInstance with configurable max_retries
- Broadcast events via Phoenix Channels for real-time TUI updates
- State persisted on terminate for crash recovery
