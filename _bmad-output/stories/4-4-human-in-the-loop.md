# Story 4.4: Human-in-the-Loop

Status: in-progress

## Story

As a user,
I want workflows to pause and wait for my approval,
So that I can intervene at key decision points.

## Acceptance Criteria

**Given** a workflow reaches an interrupt point
**When** intervention is triggered
**Then** the workflow pauses
**And** I can approve, deny, or modify via TUI
**And** workflow resumes based on my response

## Tasks / Subtasks

- [ ] Task 1 - Add interrupt stage type to Stage module [td:td-7ae0ff]
  - [x] Subtask 1.1 - Add :interrupt to stage_type
  - [x] Subtask 1.2 - Add interrupt_* fields to Stage struct
  - [x] Subtask 1.3 - Add Stage.interrupt/3 constructor
- [ ] Task 2 - Add interrupt handling to Session [td:td-7ae0ff]
  - [x] Subtask 2.1 - Add interrupt state fields to Session struct
  - [x] Subtask 2.2 - Add :awaiting_intervention status
  - [x] Subtask 2.3 - Add Session.interrupt/4 API
  - [x] Subtask 2.4 - Add Session.submit_decision/3 API
  - [x] Subtask 2.5 - Add Session.get_interrupt_state/1 API
- [ ] Task 3 - Add interrupt execution to StageExecutor [td:td-7ae0ff]
  - [x] Subtask 3.1 - Add execute_interrupt/3 function
  - [x] Subtask 3.2 - Handle interrupt stage type in execute/3

## Dev Notes

- Interrupt stages pause workflow and wait for human decision
- Session transitions to `:awaiting_intervention` state
- TUI presents options (approve/deny/modify)
- Human decision determines next stage via on_approve/on_deny/on_modify transitions

### Architecture

- New stage type: `:interrupt`
- New session status: `:awaiting_intervention`
- New Session APIs:
  - `interrupt/4` - trigger interrupt
  - `submit_decision/3` - submit human decision
  - `get_interrupt_state/1` - get pending interrupt info
  - `interrupt_pending?/1` - check if interrupt is pending

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-4.4-Human-in-the-Loop]
- [Source: _bmad-output/project-context.md#Technology-Stack]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Implemented interrupt stage type with approve/deny/modify workflow
- Added :awaiting_intervention state to session state machine
- Added Session.interrupt/4, submit_decision/3, get_interrupt_state/1, interrupt_pending?/1 APIs
- Added StageExecutor.execute_interrupt/3 for interrupt stage execution

### File List

- lib/babysitter/stage.ex
- lib/babysitter/session.ex
- lib/babysitter/stage_executor.ex

## td Integration

| Field | Value |
|-------|-------|
| td Epic ID | |
| Story File | _bmad-output/stories/4-4-human-in-the-loop.md |
| Status | in-progress |
| Sync Timestamp | 2026-02-27 |

### Task → td Mapping

| Task | td Issue ID | Status |
|------|-------------|--------|
| Task 1: Add interrupt stage type | td-7ae0ff | in-progress |
| Task 2: Add interrupt handling to Session | td-7ae0ff | in-progress |
| Task 3: Add interrupt execution to StageExecutor | td-7ae0ff | in-progress |

### td Sync Log

| Timestamp | Status | Notes |
|-----------|--------|-------|
| 2026-02-27 | initialized | Story created with interrupt stage implementation |
| 2026-02-27 | task-complete | Implemented: interrupt stage type, Session interrupt APIs, StageExecutor handler |
