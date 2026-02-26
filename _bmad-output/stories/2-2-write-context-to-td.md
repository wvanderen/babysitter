# Story 2.2: Write Context to td

Status: in-progress

<!-- BMAD-TD Integration: This story is synced with td task td-eb412e -->

## td Integration

- **td Task**: `td-eb412e`
- **Status**: in_progress
- **Last Sync**: 2026-02-26T12:00:00Z

---

## Story

As a user,
I want babysitter to write handoffs, logs, and review status back to td,
So that the next session knows what was done and what remains.

## Acceptance Criteria

1. **AC1: Handoff Creation**
   - Given a session completes or escalates
   - When babysitter writes to td
   - Then handoff is created with done/remaining/uncertain fields

2. **AC2: Log Addition**
   - Given progress or blockers occur
   - When babysitter adds logs
   - Then logs are added to the issue

3. **AC3: Review Status Update**
   - Given work is ready for review
   - When babysitter submits for review
   - Then review status is updated

## Tasks / Subtasks

- [x] Task 1: Create TD.Writer module (AC: #1, #2, #3) [td:td-eb412e]
  - [x] 1.1: Implement create_handoff/2 with done/remaining/uncertain/decisions fields
  - [x] 1.2: Implement add_log/2 with type support (progress, blocker, decision)
  - [x] 1.3: Implement submit_for_review/2
  - [x] 1.4: Implement write_context/3 for full context writing
  - [x] 1.5: Implement update_status/2 for status changes (blocked, start, approve, reject)

- [x] Task 2: Add tests for TD.Writer (AC: #1, #2, #3) [td:td-eb412e]
  - [x] 2.1: Test handoff creation with all fields
  - [x] 2.2: Test log addition with types
  - [x] 2.3: Test review submission
  - [x] 2.4: Test context writing
  - [x] 2.5: Test status updates

## Dev Notes

### Architecture Context

From architecture.md:
- FR-5: TD integration (write logs/handoffs/reviews)
- Location: `elixir/lib/babysitter/td/`

### Key Files to Create/Modify

```
elixir/
├── lib/
│   └── babysitter/
│       └── td/
│           └── writer.ex       # NEW: High-level write API
└── test/
    └── td/
        └── writer_test.exs     # NEW: Writer tests
```

### Implementation Approach

The TD.Writer module provides a high-level API on top of TD.CLI:
- `create_handoff/2` - Creates handoffs with done/remaining/uncertain/decisions
- `add_log/2` - Adds logs with type support
- `submit_for_review/2` - Submits issues for review
- `write_context/3` - Writes full context in one call
- `update_status/2` - Updates issue status (blocked, start, approve, reject)

### Testing Standards

- Tests use the actual td CLI (integration tests)
- Each test creates a temporary issue and cleans it up
- Tests verify CLI output contains expected content

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2]
- [Source: _bmad-output/planning-artifacts/architecture.md#FR-5]

## Dev Agent Record

### Agent Model Used

Claude (GLM-5) - ses_07f0f5

### Debug Log References

None required - straightforward implementation

### Completion Notes List

**Task 1 (td-eb412e): Create TD.Writer module**
- Created `Babysitter.TD.Writer` module with high-level write API
- Implemented `create_handoff/2` supporting map and keyword options
- Implemented `add_log/2` with type support (progress, blocker, decision, etc.)
- Implemented `submit_for_review/2` for review workflow
- Implemented `write_context/3` for full context writing
- Implemented `update_status/2` for status changes
- All 19 new tests passing

### File List

| File | Action | Description |
|------|--------|-------------|
| `lib/babysitter/td/writer.ex` | NEW | High-level TD write API |
| `test/td/writer_test.exs` | NEW | Writer tests (19 tests) |

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T12:00:00Z | initialized | Story created for td task td-eb412e |
| 2026-02-26T12:19Z | task-complete | td-eb412e: Create TD.Writer module |
