# Story 1.3: Validate Workflow Configuration

Status: done

<!-- BMAD-TD Integration: This story is synced with td task td-e5bc3e -->

## td Integration

- **td Issue**: `td-e5bc3e`
- **Last Sync**: 2026-02-26T15:24:00Z
- **Sync Status**: dev-complete

---

## Story

As a user,
I want workflow configuration to be validated before execution,
So that errors are caught early with helpful messages.

## Acceptance Criteria

1. **AC1: Validate Stage References**
   - Given a parsed workflow with stage transitions
   - When validation runs
   - Then all `on_success` and `on_failure` references point to existing stages
   - And `entry_point` references an existing stage

2. **AC2: Validate Required Fields**
   - Given a parsed workflow
   - When validation runs
   - Then all stages have required fields (id, type)
   - And workflow has required fields (id, name, stages)
   - And clear error messages identify missing fields

3. **AC3: Validate Intelligence Level**
   - Given a workflow with intelligence setting
   - When validation runs
   - Then intelligence is one of: `dumb`, `smart`, `hybrid`
   - And invalid values produce clear error

4. **AC4: Detect Circular References**
   - Given a workflow with stage transitions
   - When validation runs
   - Then infinite loops are detected and warned
   - And unreachable stages are identified

## Tasks / Subtasks

- [x] Task 1: Create workflow validator module (AC: #1, #2, #3)
  - [x] 1.1: Create `lib/babysitter/workflow/validator.ex` module
  - [x] 1.2: Implement `validate/1` function that takes parsed workflow
  - [x] 1.3: Return `{:ok, workflow}` or `{:error, [validation_errors]}`
  - [x] 1.4: Define `%ValidationError{}` struct for error details

- [x] Task 2: Implement stage reference validation (AC: #1)
  - [x] 2.1: Collect all stage IDs from workflow
  - [x] 2.2: Verify each `on_success` reference exists
  - [x] 2.3: Verify each `on_failure` reference exists
  - [x] 2.4: Verify `entry_point` references existing stage
  - [x] 2.5: Report missing references with stage context

- [x] Task 3: Implement required field validation (AC: #2)
  - [x] 3.1: Check workflow-level required fields
  - [x] 3.2: Check stage-level required fields based on type
  - [x] 3.3: Generate descriptive error messages with field names
  - [x] 3.4: Collect all missing fields before returning errors

- [x] Task 4: Implement intelligence level validation (AC: #3)
  - [x] 4.1: Validate intelligence is valid atom
  - [x] 4.2: Default to `hybrid` if not specified
  - [x] 4.3: Report invalid values with valid options

- [x] Task 5: Implement circular reference detection (AC: #4)
  - [x] 5.1: Build transition graph from stages
  - [x] 5.2: Detect cycles using graph traversal
  - [x] 5.3: Identify unreachable stages (not reachable from entry)
  - [x] 5.4: Return warnings (not errors) for these cases

## Dev Notes

### Architecture Context

From architecture.md:
- Workflow validation should happen before execution
- Errors should be caught early with helpful messages
- Validation is part of FR-1 (Workflow definition and execution)

### Key Files Created

```
lib/babysitter/workflow/
├── validation_error.ex   # NEW: ValidationError struct
└── validator.ex          # NEW: Workflow validation logic

test/workflow/
└── validator_test.exs    # NEW: 27 unit tests
```

## File List

| File | Status | Description |
|------|--------|-------------|
| `lib/babysitter/workflow/validation_error.ex` | NEW | ValidationError struct with factory functions |
| `lib/babysitter/workflow/validator.ex` | NEW | Workflow validator with all AC validations |
| `test/workflow/validator_test.exs` | NEW | 27 unit tests covering all acceptance criteria |

### Validation Error Structure

```elixir
defmodule Babysitter.Workflow.ValidationError do
  @type t :: %__MODULE__{
    type: :missing_field | :invalid_reference | :invalid_value | :circular_reference | :unreachable_stage,
    field: atom(),
    stage_id: String.t() | nil,
    message: String.t(),
    details: map()
  }
end
```

### Validator Implementation Pattern

```elixir
defmodule Babysitter.Workflow.Validator do
  alias Babysitter.Workflow.ValidationError

  @spec validate(map()) :: {:ok, map()} | {:error, [ValidationError.t()]}
  def validate(workflow) do
    errors = 
      []
      |> validate_required_fields(workflow)
      |> validate_stage_references(workflow)
      |> validate_intelligence(workflow)
      |> detect_circular_references(workflow)
    
    case errors do
      [] -> {:ok, workflow}
      errors -> {:error, errors}
    end
  end
end
```

### Testing Standards

- Unit tests for each validation type
- Test valid workflow passes all validations
- Test each error type produces correct error structure
- Test multiple errors collected at once
- Test edge cases (empty stages, self-references)

### Integration Point

Validator should be called after Parser parses workflow:

```elixir
with {:ok, workflow} <- Parser.parse_file(path),
     {:ok, workflow} <- Validator.validate(workflow) do
  {:ok, workflow}
end
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#FR-1]
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3]
- [Source: lib/babysitter/workflow/parser.ex - existing parser]

---

## Senior Developer Review (AI)

**Date:** 2026-02-26
**Outcome:** Approved with fixes applied
**Action Items:** 0 (all resolved during review)

### Summary
All 4 acceptance criteria implemented correctly. One MEDIUM issue found during review (incomplete cycle detection) - fixed during review session. Two additional tests added for on_failure and on_timeout cycle paths. All 29 tests passing.

### Issues Found and Resolved
- [x] [MEDIUM] Cycle detection only followed on_success path - now explores all transition types

### Test Coverage
- 29 unit tests (27 original + 2 new for complete cycle detection)
- All ACs covered with multiple test cases each

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T15:45:00Z | initialized | Story created, unblocked after Story 1.2 completion |
| 2026-02-26T15:24:00Z | dev-complete | All 5 tasks implemented with 27 passing tests |
| 2026-02-26T16:30:00Z | reviewed | Epic review complete, fixed cycle detection, added 2 tests |

## Completion Notes

**Implementation Summary:**
- Created `ValidationError` struct with typed error types and factory functions
- Implemented `Validator.validate/1` with comprehensive validation pipeline
- Validates stage references (on_success, on_failure, on_timeout, entry_point)
- Validates required workflow fields (id, name, stages)
- Validates intelligence level (dumb/smart/hybrid)
- Detects circular references as warnings (not errors) - explores ALL transition types
- Identifies unreachable stages as warnings
- 29 unit tests, all passing

**Key Decisions:**
- Circular references and unreachable stages are warnings, not errors - allows retry patterns
- ValidationError struct provides factory functions for consistent error creation
- Validation errors are collected before returning (fail-fast would hide multiple issues)
- Cycle detection explores on_success, on_failure, and on_timeout paths
