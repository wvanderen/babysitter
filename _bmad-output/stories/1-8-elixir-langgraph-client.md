# Story 1.8: Elixir LangGraph Client

Status: ready-for-dev

## Story

As a developer,
I want an Elixir client module for LangGraph API,
So that Elixir can manage workflow threads and runs.

## Acceptance Criteria

1. **AC1: Thread Management**
   - Given LangGraph service is running
   - When Elixir calls the client
   - Then `Babysitter.LangGraph.Client` can create threads
   - And threads can be retrieved by ID

2. **AC2: Run Lifecycle**
   - Given a thread exists
   - When Elixir starts a run
   - Then runs can be started with input payloads
   - And runs can be stopped/cancelled
   - And run status can be polled

3. **AC3: Interrupt/Resume**
   - Given a run is in interrupted state
   - When Elixir calls resume
   - Then the run continues with the provided resume value

4. **AC4: Error Handling**
   - Given LangGraph returns an error
   - When any client function is called
   - Then errors are handled with 3x retry
   - And exponential backoff is applied (1s, 2s, 4s)

## Tasks / Subtasks

- [x] Task 1: Implement run lifecycle functions (AC: #2) [td:td-289b2c]
  - [x] 1.1: Add `get_run/2` to fetch run details
  - [x] 1.2: Add `get_run_status/2` to poll run status
  - [x] 1.3: Add `cancel_run/2` to stop/cancel a running run
  - [x] 1.4: Add `list_runs/1` to list all runs for a thread
  - [x] 1.5: Update `create_run/2` to support all LangGraph options (stream_mode, etc.)

- [x] Task 2: Implement interrupt/resume functions (AC: #3) [td:td-50b572]
  - [x] 2.1: Add `resume_run/3` with resume value support
  - [x] 2.2: Add support for different command types (resume, approve, reject)
  - [x] 2.3: Handle interrupted state detection in `get_run_status/2`

- [x] Task 3: Add comprehensive tests (AC: #1, #2, #3, #4) [td:td-6c2d16]
  - [x] 3.1: Add unit tests for new functions
  - [x] 3.2: Add integration tests against running LangGraph service
  - [x] 3.3: Add retry logic tests for error scenarios
  - [x] 3.4: Add tests for all command types (resume, approve, reject)

- [x] Task 4: Update documentation (AC: #1, #2, #3, #4) [td:td-18aa0c]
  - [x] 4.1: Add @moduledoc with usage examples
  - [x] 4.2: Add @doc for all public functions
  - [x] 4.3: Add typespec for all public functions

## Dev Notes

### Architecture Context

From architecture.md:
- **State Authority:** Elixir owns session state, LangGraph is stateless compute engine
- **Communication:** REST + polling (2-3s interval)
- **Error Handling:** Retry 3x with exponential backoff (1s, 2s, 4s), then escalate
- **Timeout:** 30 seconds per request

### Existing Implementation

Story 1.7 already implemented basic client in `lib/babysitter/langgraph/client.ex`:
- `health_check/0` - Check service health
- `create_thread/0`, `create_thread/1` - Create threads
- `get_thread/1` - Get thread by ID
- `create_run/2` - Start a run with input
- `get_state/1` - Get thread state
- `with_retry/2` - Retry logic with exponential backoff
- `healthy?/0` - Boolean health check

### LangGraph Platform API Endpoints

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `POST /threads` | Create new thread | ✅ Implemented |
| `GET /threads/{id}` | Get thread by ID | ✅ Implemented |
| `POST /threads/{id}/runs` | Start workflow execution | ✅ Implemented |
| `GET /threads/{id}/runs/{run_id}` | Get run details | ✅ Implemented |
| `GET /threads/{id}/runs/{run_id}/status` | Poll for status | ✅ Implemented |
| `POST /threads/{id}/runs/{run_id}` | Resume after interrupt | ❌ Needed |
| `DELETE /threads/{id}/runs/{run_id}` | Cancel (timeout) | ✅ Implemented |
| `GET /threads/{id}/runs` | List runs for thread | ✅ Implemented |

### API Response Structures

**Run Status Response:**
```json
{
  "run_id": "run_abc123",
  "thread_id": "th_xyz789",
  "status": "running|pending|interrupted|completed|error|cancelled",
  "created_at": "2026-02-27T10:00:00Z"
}
```

**Resume Request:**
```json
{
  "command": {
    "resume": "approved"
  }
}
```

Or with value:
```json
{
  "command": {
    "resume": {"action": "retry", "context": "..."}
  }
}
```

### State Mapping (from architecture.md)

| LangGraph Status | Elixir Session State |
|------------------|---------------------|
| `pending` | `initializing` |
| `running` | `running` |
| `interrupted` | `paused` |
| `completed` | `completed` |
| `error` | `failed` |
| `cancelled` | `stopped` |

### Implementation Notes

1. **Run Status Polling**: Use 2-second polling interval as per architecture
2. **Resume Commands**: Support multiple command types:
   - `{:resume, value}` - Resume with value
   - `:approve` - Approve and continue
   - `:reject` - Reject and stop
3. **Error Handling**: Leverage existing `with_retry/2` for all new functions
4. **Type Safety**: Add typespecs for all public functions

### Dependencies

- Story 1.7 (LangGraph Infrastructure Setup) - COMPLETE
- Tesla HTTP client with Finch adapter - COMPLETE
- LangGraph service running on 127.0.0.1:8123

### Testing Strategy

1. **Unit tests**: Mock Tesla adapter for API responses
2. **Integration tests**: Run against actual LangGraph service (auto-skip if unavailable)
3. **Retry tests**: Use counter-based verification like existing tests

---

## td Integration

- **td Epic**: `td-4c2869`
- **td Tasks**: 4 issues created
- **Last Sync**: 2026-02-27T10:00:00Z
- **Sync Status**: initialized

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1: Implement run lifecycle functions | `td-289b2c` | in_review |
| Task 2: Implement interrupt/resume functions | `td-50b572` | in_review |
| Task 3: Add comprehensive tests | `td-6c2d16` | in_review |
| Task 4: Update documentation | `td-18aa0c` | in_review |

---

## File List

| File | Change |
| |------|--------|
| `lib/babysitter/langgraph/client.ex` | Added get_run/2, get_run_status/2, cancel_run/2, list_runs/1, updated create_run/2, resume_run/3, interrupted?/2 |
| `test/langgraph/client_test.exs` | Added comprehensive unit tests, integration tests, retry tests, and command type tests |

---

## Dev Agent Record

### Completion Notes

**Task 1: Run Lifecycle Functions (2026-02-27)**
- Implemented `get_run/2` - fetch run details by thread_id and run_id
- Implemented `get_run_status/2` - poll run status
- Implemented `cancel_run/2` - cancel running runs via DELETE
- Implemented `list_runs/1` - list all runs for a thread
- Enhanced `create_run/2` with optional params: stream_mode, config, webhook
- All functions use existing `with_retry/2` for error handling
- Added typespecs for all public functions
- Added unit tests with mock Tesla adapter

**Task 2: Interrupt/Resume Functions (2026-02-27)**
- Implemented `resume_run/3` - resume interrupted runs with command types
- Added command type support: `{:resume, value}`, `:approve`, `:reject`
- Implemented `interrupted?/2` - check if run is in interrupted state
- Uses existing `with_retry/2` for error handling
- Added typespecs and @doc for all new functions
- Added unit tests for all command types and interrupted state detection

**Task 3: Comprehensive Tests (2026-02-27)**
- Added unit tests for all new functions: get_run/2, get_run_status/2, cancel_run/2, list_runs/1, resume_run/3, interrupted?/2
- Added integration tests against running LangGraph service with auto-skip if unavailable
- Added retry logic tests for different error types (timeout, econnrefused, nxdomain)
- Added tests for all command types: :approve, :reject, {:resume, value} with complex, string, and list values
- Added error handling tests for 404 responses
- Added tests for create_run/2 with optional params (stream_mode, config, webhook)
- Total: 35 tests (27 unit + 8 integration), all passing

**Task 4: Update Documentation (2026-02-27)**
- Enhanced @moduledoc with comprehensive usage examples
- Added Configuration section with environment variables
- Added usage examples for: health check, thread management, run lifecycle, interrupt/resume flow
- Added error handling documentation
- Added state mapping table (LangGraph status to description)
- All public functions already had @doc and @spec from previous tasks

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-27T10:00:00Z | story-created | Story 1.8 created with td epic td-4c2869 |
| 2026-02-27T10:00:00Z | tasks-created | Created 4 td issues under epic td-4c2869 |
| 2026-02-27T09:52:00Z | task-complete | td-289b2c: Task 1: Implement run lifecycle functions |
| 2026-02-27T09:56:00Z | task-complete | td-50b572: Task 2: Implement interrupt/resume functions |
| 2026-02-27T10:04:00Z | task-complete | td-6c2d16: Task 3: Add comprehensive tests |
| 2026-02-27T10:12:00Z | task-complete | td-18aa0c: Task 4: Update documentation |
