# Story 1.3: Validate Workflow Configuration

Status: ready-for-dev

<!-- BMAD-TD Integration: This story is synced with td task td-e5bc3e -->

## td Integration

- **td Issue**: `td-e5bc3e`
- **Last Sync**: 2026-02-26T15:45:00Z
- **Sync Status**: initialized

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

- [ ] Task 1: Create workflow validator module (AC: #1, #2, #3)
  - [ ] 1.1: Create `lib/babysitter/workflow/validator.ex` module
  - [ ] 1.2: Implement `validate/1` function that takes parsed workflow
  - [ ] 1.3: Return `{:ok, workflow}` or `{:error, [validation_errors]}`
  - [ ] 1.4: Define `%ValidationError{}` struct for error details

- [ ] Task 2: Implement stage reference validation (AC: #1)
  - [ ] 2.1: Collect all stage IDs from workflow
  - [ ] 2.2: Verify each `on_success` reference exists
  - [ ] 2.3: Verify each `on_failure` reference exists
  - [ ] 2.4: Verify `entry_point` references existing stage
  - [ ] 2.5: Report missing references with stage context

- [ ] Task 3: Implement required field validation (AC: #2)
  - [ ] 3.1: Check workflow-level required fields
  - [ ] 3.2: Check stage-level required fields based on type
  - [ ] 3.3: Generate descriptive error messages with field names
  - [ ] 3.4: Collect all missing fields before returning errors

- [ ] Task 4: Implement intelligence level validation (AC: #3)
  - [ ] 4.1: Validate intelligence is valid atom
  - [ ] 4.2: Default to `hybrid` if not specified
  - [ ] 4.3: Report invalid values with valid options

- [ ] Task 5: Implement circular reference detection (AC: #4)
  - [ ] 5.1: Build transition graph from stages
  - [ ] 5.2: Detect cycles using graph traversal
  - [ ] 5.3: Identify unreachable stages (not reachable from entry)
  - [ ] 5.4: Return warnings (not errors) for these cases

## Dev Notes

### Architecture Context

From architecture.md:
- Workflow validation should happen before execution
- Errors should be caught early with helpful messages
- Validation is part of FR-1 (Workflow definition and execution)

### Key Files to Create/Modify

```
lib/
├── babysitter/
│   └── workflow/
│       └── validator.ex       # NEW: Validation logic
test/
└── workflow/
    └── validator_test.exs     # NEW
```

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

**Date:** Pending
**Outcome:** Pending
**Action Items:** Pending

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-26T15:45:00Z | initialized | Story created, unblocked after Story 1.2 completion |
